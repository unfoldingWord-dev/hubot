module.exports = function(robot) {
	// msg holds the string after bible me
    robot.hear(/bible me(.*)/i, function(msg) {
        //get the json file from the following URL
        robot.http("https://api.unfoldingword.org/uw/txt/2/catalog.json").get()(function(err, res, body) {
            //parse the json file accessed from the URL
            catalog = JSON.parse(body);
			bible_version = "ulb";
			bv = 1;
			inputSelection = msg.match[1].split(" ");
			last_value = inputSelection[inputSelection.length-1];
			
			if (last_value == "udb"){
				bible_version = "udb";
				bv = 0;
			}
			
            numBooks = catalog.cat[0].langs[1].vers[bv].toc.length;
            bookNum = Math.floor(Math.random() * numBooks);
            bookURL = catalog.cat[0].langs[1].vers[bv].toc[bookNum].src;
            bookSlug = catalog.cat[0].langs[1].vers[bv].toc[bookNum].slug;
			//msg.send(bookURL);
			//msg.send(bookSlug);

            if (inputSelection.length == 1 || (inputSelection.length == 2 && (last_value == "udb" || last_value == "ulb")) ){
                //msg.send("pick random");
                current = "";
                processCatalog(catalog, current);
                    //msg.send(bookURL);
                book = robot.http(bookURL).get()(function(err, res, body) {
                                    verse = "test";

                        processUSFMDocument(body, verse, msg,0,0,0, bible_version);
                        //output the string verse

                });
            }
            else{
                //msg.send("book is " + inputSelection[1]);
				
				if(inputSelection[1] == 'Song' && inputSelection[2] == 'of'){
					inputSelection[1] = inputSelection[1] + " " + inputSelection[2] + " " + inputSelection[3];
					inputSelection[2] = inputSelection[4];
				}
				
                if(inputSelection[1] == '1' || inputSelection[1] == '2' || inputSelection[1] == '3'){
                    inputSelection[1] = inputSelection[1] + " " + inputSelection[2];
                    inputSelection[2] = inputSelection[3];
                    //msg.send("book is now " + inputSelection[1]);
					//msg.send("book is now " + inputSelection[2]);
                }
                var found = false;
                var bookName = null;
                var chapter = null;
                var verse = null;
                //msg.send(inputSelection[1]);
				
				long_bookName = short_book(inputSelection[1]);
				
				//msg.send(long_bookName);
                for(var i = 0; i < numBooks; i++){
                    //msg.send("trying... " + catalog.cat[0].langs[1].vers[1].toc[i].title);
                    if(strCmp(long_bookName, catalog.cat[0].langs[1].vers[1].toc[i].title) == true){
                        //msg.send("found");
                        found = true;
                        bookName = long_bookName;
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
				//msg.send(verse);
				start_verse = 1;
				end_verse = 0;
				if (verse != undefined) {
					verse_range = verse.split("-");
					start_verse = verse_range[0];
					end_verse = verse_range[1];
				}
				if (end_verse == undefined){
					end_verse = start_verse;
					end_verse = start_verse;
				}
				
                //msg.send("start verse is: " + start_verse);
                //msg.send("end verse is: " + end_verse);
				
                bookURL = catalog.cat[0].langs[1].vers[bv].toc[bookNum].src;
                bookSlug = catalog.cat[0].langs[1].vers[bv].toc[bookNum].slug;

                book = robot.http(bookURL).get()(function(err, res, body) {
                                    current = "";

                        processUSFMDocument(body, current, msg,chapter,start_verse,end_verse, bible_version);
                        //output the string verse

                });
            }
        });
    });
};

function strCmp(string1, string2) {
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
		else if(entry["slug"] == "udb"){
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

function processUSFMDocument(doc, returnVerse, msg, chapter, startVerse, endVerse, bible_version) {
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
        reference = getReference(verse["book"], bookSlug, verse["chapter"], verse["verse"], bible_version);
    }else{
        reference = getReference(verse["book"], bookSlug, verse["chapter"], startVerse + "-" + verse["verse"], bible_version);
    }
    
    msg.send(returnVerse);
    msg.send(reference);
}

function getReference(book, sl, chapter, verse, bible_version) {
    var ref = " - " + book + " " + chapter + ":" + verse;
    return ref+"\nhttps://door43.org/en/" + bible_version +  "/v1/"+ sl + "/" + getChapter(chapter) + ".usfm";
}

function getChapter(chapter) {
    var temp;
    if(chapter.length == 1)
        temp = "00" + chapter;
    else if(chapter.length == 2)
        temp = "0" + chapter;
    else
        temp = "001";
    return temp;
}

function short_book(bookName) {
	if (bookName == "Gen" || bookName == "Ge" || bookName == "Gn"){
		return "Genesis";
	}
	else if (bookName == "Exo" || bookName == "Ex" || bookName == "Exod"){
		return "Exodus";
	}
	else if (bookName == "Lev" || bookName == "Le" || bookName == "Lv"){
		return "Leviticus";
	}
	else if (bookName == "Num" || bookName == "Nu" || bookName == "Nm" || bookName == "Nb"){
		return "Numbers";
	}
	else if (bookName == "Deut" || bookName == "Dt"){
		return "Deuteronomy";
	}
	else if (bookName == "Josh" || bookName == "Jos" || bookName == "Jsh"){
		return "Joshua";
	}
	else if (bookName == "Judg" || bookName == "Jdg" || bookName == "Jg" || bookName == "Jdgs"){
		return "Judges";
	}
	else if (bookName == "Rth" || bookName == "Ru"){
		return "Ruth";
	}
	else if (bookName == "1 Sam" || bookName == "1 Sa"){
		return "1 Samuel";
	}
	else if (bookName == "2 Sam" || bookName == "2 Sa"){
		return "2 Samuel";
	}
	else if (bookName == "1 Kgs" || bookName == "1 Ki"){
		return "1 Kings";
	}
	else if (bookName == "2 Kgs" || bookName == "2 Ki"){
		return "2 Kings";
	}
	else if (bookName == "1 Chron" || bookName == "1 Ch"){
		return "1 Chronicles";
	}
	else if (bookName == "2 Chron" || bookName == "2 Ch"){
		return "2 Chronicles";
	}
	else if (bookName == "Ezr"){
		return "Ezra";
	}
	else if (bookName == "Neh" || bookName == "Ne"){
		return "Nehemiah";
	}
	else if (bookName == "Esth" || bookName == "Es"){
		return "Esther";
	}
	else if (bookName == "Jb"){
		return "Job";
	}
	else if (bookName == "Psalms" || bookName == "Pslm" || bookName == "Ps"){
		return "Psalm";
	}
	else if (bookName == "Prov" || bookName == "Pr" || bookName == "Prv"){
		return "Proverbs";
	}
	else if (bookName == "Eccles" || bookName == "Ec" || bookName == "Ecc"){
		return "Ecclesiastes";
	}
	else if (bookName == "Song" || bookName == "So" || bookName == "Song of Songs"){
		return "Song of Solomon";
	}
	else if (bookName == "Isa" || bookName == "Is"){
		return "Isaiah";
	}
	else if (bookName == "Jer" || bookName == "Je" || bookName == "Jr"){
		return "Jeremiah";
	}
	else if (bookName == "Lam" || bookName == "La"){
		return "Lamentations";
	}
	else if (bookName == "Ezek" || bookName == "Eze" || bookName == "Ezk"){
		return "Ezekiel";
	}
	else if (bookName == "Dan" || bookName == "Da" || bookName == "Dn"){
		return "Daniel";
	}
	else if (bookName == "Hos" || bookName == "Ho"){
		return "Hosea";
	}
	else if (bookName == "Joe" || bookName == "Jl"){
		return "Joel";
	}
	else if (bookName == "Am"){
		return "Amos";
	}
	else if (bookName == "Obad" || bookName == "Ob"){
		return "Obadiah";
	}
	else if (bookName == "Jnh" || bookName == "Jon"){
		return "Jonah";
	}
	else if (bookName == "Joe"){
		return "Micah";
	}
	else if (bookName == "Nah" || bookName == "Na"){
		return "Nahum";
	}
	else if (bookName == "Hab"){
		return "Habakkuk";
	}
	else if (bookName == "Zeph" || bookName == "Zep" || bookName == "Zp"){
		return "Zephaniah";
	}
	else if (bookName == "Hag" || bookName == "Hg"){
		return "Haggai";
	}
	else if (bookName == "Zech" || bookName == "Zec" || bookName === "Zc"){
		return "Zechariah";
	}
	else if (bookName == "Mal" || bookName == "Ml"){
		return "Malachi";
	}
	else if (bookName == "Matt" || bookName == "Mt" || bookName == "Mat"){
		return "Matthew";
	}
	else if (bookName == "Mrk" || bookName == "Mk" || bookName == "Mr"){
		return "Mark";
	}
	else if (bookName == "Luk" || bookName == "Lk"){
		return "Luke";
	}
	else if (bookName == "Jn" || bookName == "Jhn"){
		return "John";
	}
	else if (bookName == "Ac"){
		return "Acts";
	}
	else if (bookName == "Rom" || bookName == "Ro" || bookName == "Rm"){
		return "Romans";
	}
	else if (bookName == "1 Cor" || bookName == "1 Co"){
		return "1 Corinthians";
	}
	else if (bookName == "2 Cor" || bookName == "2 Co"){
		return "2 Corinthians";
	}
	else if (bookName == "Gal" || bookName == "Ga"){
		return "Galatians";
	}
	else if (bookName == "Ephes" || bookName == "Eph"){
		return "Ephesians";
	}
	else if (bookName == "Phil" || bookName == "Php"){
		return "Philippians";
	}
	else if (bookName == "Col"){
		return "Colossians";
	}
	else if (bookName == "1 Thess" || bookName == "1 Th"){
		return "1 Thessalonians";
	}
	else if (bookName == "2 Thess" || bookName == "2 Th"){
		return "2 Thessalonians";
	}
	else if (bookName == "1 Tim" || bookName == "1 Ti"){
		return "1 Timothy";
	}
	else if (bookName == "2 Tim" || bookName == "2 Ti"){
		return "2 Timothy";
	}
	else if (bookName == "Tit"){
		return "Titus";
	}
	else if (bookName == "Philem" || bookName == "Phm"){
		return "Philemon";
	}
	else if (bookName == "Heb"){
		return "Hebrews";
	}
	else if (bookName == "Jas" || bookName == "Jm"){
		return "James";
	}
	else if (bookName == "1 Pet" || bookName == "1 Pe"){
		return "1 Peter";
	}
	else if (bookName == "2 Pet" || bookName == "2 Pe"){
		return "2 Peter";
	}
	else if (bookName == "1 Jn" || bookName == "1 Jhn"){
		return "1 John";
	}
	else if (bookName == "2 Jn" || bookName == "2 Jhn"){
		return "2 John";
	}
	else if (bookName == "3 Jn" || bookName == "3 Jhn"){
		return "3 John";
	}
	else if (bookName == "Jud"){
		return "Jude";
	}
	else if (bookName == "Rev" || bookName == "Re"){
		return "Revelation";
	}
	return bookName;
}