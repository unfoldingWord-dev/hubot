# Description:
#   Search the translation database
#
# Commands:
#   hubot td "query" - search translation database for "query"

module.exports = (robot) ->
  robot.languages ||= {'languages':[],'lastUpdated': 0} # stores cache of langnames.json

  get_languages = (callback) ->
    if robot.languages.lastUpdated < (Date.now() - 60*60*1000) # 1 hr cache time
      robot.http("http://td.unfoldingword.org/exports/langnames.json")
      .get() (error, response, body) ->

        if error
          console.log "Encountered and error :( #{error}"
          return

        if response.statusCode isnt 200
          console.log "Request didn't come back HTTP 200 :("
          return

        robot.languages.languages = JSON.parse(body)
        robot.languages.lastUpdated = Date.now()

        callback(robot.languages.languages)
    else 
        callback(robot.languages.languages)

  search_languages = (query, callback) ->
    
    get_languages (languages) ->
      results = []
      for language in languages

        score = 0
        if query == language.lc.toLowerCase()
          score += 1000   # code is an exact match of query
        if language.lc.toLowerCase().indexOf(query) == 0
          score += 500    # code starts with query
        if query == language.ln.toLowerCase()
          score += 100    # language name is an exact match

        positionLn = language.ln.toLowerCase().indexOf(query)

        if positionLn != -1 
          score += 10 * ((language.ln.length - positionLn) / language.ln.length)
          # language name contains query, higher score if the query matches something at the bigging of the language name

        if score > 0
          results.push({'pk': language.pk, 'ln':language.ln, 'lc': language.lc, 'score':score})

      results.sort (a,b) ->
        return b.score-a.score # sort descending
      
      callback(results)
    
  robot.respond /td (.*)/i, (res) ->
   query = res.match[1].toLowerCase()
   
   results = search_languages query, (results) -> 
   
    if results.length
       for result in results.slice(0, 3)
         res.send "#{result.lc} #{result.ln} http://td.unfoldingword.org/uw/languages/#{result.pk}/"
     else
       res.send "Nothing found for #{query}, sorry"
          