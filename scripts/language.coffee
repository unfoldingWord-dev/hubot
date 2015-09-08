# Description:
#   Search the translation database
#
# Commands:
#   hubot td "query" - search translation database for "query"

module.exports = (robot) ->

  robot.respond /td (.*)/i, (res) ->
   query = res.match[1].toLowerCase()
   
   robot.http("http://td.unfoldingword.org/exports/langnames.json")
      .get() (error, response, body) ->

        if error
          console.log "Encountered and error :( #{error}"
          return

        if response.statusCode isnt 200
          console.log "Request didn't come back HTTP 200 :("
          return

        languages = JSON.parse(body)
        results = []
        for language in languages
        
          score = 0
          if query == language.lc.toLowerCase()
            score += 1000
          if query == language.ln.toLowerCase()
            score += 100
          position = language.ln.toLowerCase().indexOf(query)
          
          if position != -1 
            score += 10 * ((language.ln.length - position) / language.ln.length)
            
          if score > 0
            results.push({'pk': language.pk, 'ln':language.ln, 'lc': language.lc, 'score':score})
        
        results.sort (a,b) ->
          return b.score-a.score # sort descending
        
        if result.length
          for result in results.slice(0, 3)
            res.send "#{result.lc} #{result.ln} http://td.unfoldingword.org/uw/languages/#{result.pk}/"
        else
          res.send "Nothing found for #{query}, sorry"
            
        
          