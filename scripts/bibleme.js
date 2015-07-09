module.exports = function(robot){
    robot.hear(/bible me(.*)/i, function(msg) {

        //get the json file from the following URL
        robot.http("https://api.unfoldingword.org/uw/txt/2/catalog.json").get()(function(err, res, body) {
            //parse the json file accessed from the URL
            catalog = JSON.parse(body);
            numBooks = catalog.cat[0].langs[1].vers[1].toc.length;
            bookNum = Math.floor(Math.random() * numBooks);
            bookURL = catalog.cat[0].langs[1].vers[1].toc[bookNum].src;
            bookSlug = catalog.cat[0].langs[1].vers[1].toc[bookNum].slug;

            inputSelection = msg.match[1].split(" ");
            if (inputSelection.length == 1){
                //msg.send("pick random");
                current = "";
                processCatalog(catalog, current);
                    //msg.send(bookURL);
                book = robot.http(bookURL).get()(function(err, res, body) {
                                    verse = "test";

                        processUSFMDocument(body, verse, msg,0,0,0);
                        //output the string verse

                });
            }
            else{
                //msg.send("book is " + inputSelection[1]);
                if(inputSelection[1] == "1" || inputSelection[1] == '2' || inputSelection[1] == '3'){
                    inputSelection[1] = inputSelection[1] + " " + inputSelection[2];
                    inputSelection[2] = inputSelection[3];
                    //msg.send("book is now " + inputSelection[1]);
                }
                var found = false;
                var bookName = null;
                var chapter = null;
                var verse = null;
                //msg.send(inputSelection);
                for(var i = 0; i < numBooks; i++){
                    //msg.send("trying... " + catalog.cat[0].langs[1].vers[1].toc[i].title);
                    if(strCmp(inputSelection[1], catalog.cat[0].langs[1].vers[1].toc[i].title) == true){
                        //msg.send("found");
                        found = true;
                        bookName = inputSelection[1];
                        bookNum = i;
                        break;
                    }
                }
                if(!found){
                    msg.send("Sorry, could not find the book: " + inputSelection[1]);
                }

                verseChapter = inputSelection[2].split(":");
                chapter = verseChapter[0];
                verse = verseChapter[1];
                //msg.send("chapter is: " + chapter);
                //msg.send("verse is: " + verse);
                bookURL = catalog.cat[0].langs[1].vers[1].toc[bookNum].src;
                bookSlug = catalog.cat[0].langs[1].vers[1].toc[bookNum].slug;

                book = robot.http(bookURL).get()(function(err, res, body) {
                                    current = "";

                        processUSFMDocument(body, current, msg,chapter,verse,verse);
                        //output the string verse

                });
            

            }
        });
    });

};

function strCmp(string1, string2){
    str1 = string1.toLowerCase();
    str2 = string2.toLowerCase();
    if(str1.length == str2.length){
        for(var i = 0; i < str1.length; i++){
            if(str1[i] === str2[i]){
                continue;
            }
            else{
                return false;
            }
        }
        return true;
    }
    return false;
}

function processCatalog(data, current) {
    catalog = data["cat"];
    for (i = 0; i < catalog.length; i++) {
        entry = catalog[i];
        if (entry["slug"] == "bible") {
            current = processBible(entry, current);
            break;
        }
    }
}

function processBible(data, current) {
    languages = data["langs"]
    for (i = 0; i < languages.length; i++) {
        entry = languages[i];
        if (entry["lc"] == "en") {
            current = processEnglishBible(entry, current);
            break;
        }
    }
}

function processEnglishBible(data, current) {
    versions = data["vers"]
    for (i = 0; i < versions.length; i++) {
        entry = versions[i];
        if (entry["slug"] == "ulb") {
            current = processEnglishLiteralBible(entry, current);
            break;
        }
    }
}

function processEnglishLiteralBible(data, current) {
    toc = data["toc"];
    bookNum = Math.floor(Math.random() * toc.length);
    book = toc[bookNum];
    src = book["src"];
    current = src;
}

function processBook(src, verse) {
    var xmlhttp = new XMLHttpRequest();
    xmlhttp.onreadystatechange = function() {
        if (xmlhttp.readyState == 4 && xmlhttp.status == 200) {
            verse = processUSFMDocument(xmlhttp.responseText, verse);
        }
    }
    xmlhttp.open("GET", src, true);
    xmlhttp.send();
}

function processUSFMDocument(doc, returnVerse, msg, chapter, startVerse, endVerse) {
    var currentBook = "";
    var currentChapter = "";
    var verses = [];
    var lines = doc.split("\n");
    
    var startVerse = startVerse;
    var endVerse = endVerse;
    var sVerse = -1;
    var count = -2;
    
    for (i = 0; i < lines.length; i++) {
        line = lines[i];
        indexOfFirstSpace = line.indexOf(" ");
        if (indexOfFirstSpace == -1) {
            continue;
        }
        dataType = line.substring(0, indexOfFirstSpace);
        if (dataType == "\\v") {
            indexOfSecondSpace = line.indexOf(" ", indexOfFirstSpace + 1);
            verseNumber = line.substring(indexOfFirstSpace + 1, indexOfSecondSpace);
            if(chapter == 0){
                //randomize
                verses.push({"book": currentBook, "chapter": currentChapter, "verse": verseNumber, "text": line.substring(indexOfSecondSpace + 1)});
            }
            else if(currentChapter == chapter ){
                //if specific verse range
                if(startVerse != 0 && endVerse != 0){
                    if((sVerse == -1)){
                        //start verse
                        sVerse = verseNumber;
                        count = -1;
                    }
                    if((verseNumber - sVerse + 1) == startVerse){
                        count = 0;
                    }
                    //distance
                    if((count >= 0) && (count <= (endVerse-startVerse))){
                        count++;
                        verses.push({"book": currentBook, "chapter": currentChapter, "verse": verseNumber, "text": line.substring(indexOfSecondSpace + 1)});
                    }
                }
                else{
                    //get entire book
                    verses.push({"book": currentBook, "chapter": currentChapter, "verse": verseNumber, "text": line.substring(indexOfSecondSpace + 1)});
                }
            }else{
                //
            }
        } else if (dataType == "\\c") {
            currentChapter = line.substring(indexOfFirstSpace + 1);
        } else if (dataType == "\\h") {
            currentBook = line.substring(indexOfFirstSpace + 1);
        }
    }
    if(chapter == 0 && startVerse == 0 && endVerse == 0){
        verseNum = Math.floor(Math.random() * verses.length);
        //verseNum = 
        verse = verses[verseNum];
        returnVerse =  verse["text"];
    }else{
    //print range of verses
    for(var x =0; x < verses.length; x++){
        //verseNum = x;
        verse = verses[x];
        returnVerse += verse["text"];
    }
    }
    if(startVerse == endVerse){
        reference = getReference(verse["book"], bookSlug, verse["chapter"], verse["verse"]);
    }else{
        reference = getReference(verse["book"], bookSlug, verse["chapter"], startVerse + "-" + verse["verse"]);
    }
    
    msg.send(returnVerse);
    msg.send(reference);
}



function getReference(book, sl, chapter, verse){
    var ref = " - " + book + " " + chapter + ":" + verse;
    return ref+"\nhttps://door43.org/en/ulb/v1/" + sl + "/" + getChapter(chapter) + ".usfm";
}

function getChapter(chapter){
    var temp;
    if(chapter.length == 1)
        temp = "00" + chapter;
    else if(chapter.length == 2)
        temp = "0" + chapter;
    else
        temp = "001";
    return temp;
}
