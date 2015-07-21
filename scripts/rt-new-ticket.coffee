###
  Description:
    Login to request tracker and check for tickets that are New and Unowned
    post those tickets to the #helpdesk channel with #<ticket-number> and subject

  Configuration:
    process.env.BOT_RT_BASE_URL (format: "https://help.door43.org/")
    process.env.BOT_RT_USERNAME
    process.env.BOT_RT_PASSWORD
###

rtUrl = process.env.BOT_RT_BASE_URL
unless rtUrl?
  console.log "Missing BOT_RT_BASE_URL in environment: please set and try again"
  process.exit(1)

username = process.env.BOT_RT_USERNAME
unless username?
  console.log "Missing BOT_RT_USERNAME in environment: please set and try again"
  process.exit(1)

password = process.env.BOT_RT_PASSWORD
unless password?
  console.log "Missing BOT_RT_PASSWORD in environment: please set and try again"
  process.exit(1)


module.exports = (robot) ->


  robot.on 'slave:newTicket', ->
    helpDeskChannel = '#helpdesk'
    robot.messageRoom helpDeskChannel, "Slave: Finding last hours new unowned tickets", ->

    auth = 'Basic' + new Buffer(username + ':' + password).toString('base64');
    queryStr = "%20Owner%20=%20%27Nobody%27%20AND%20(Status%20=%20%27new%27%20OR%20Status%20=%20%27open%27)"
    robot.http("#{rtUrl}/REST/1.0/search/ticket?query=#{queryStr}&format=s")
      .headers(Authorization: auth, Content-Type: 'application/json')
      .get() (error, response, body) ->

        if error
          console.log "Encountered and error :( #{error}"
          return

        if statusCode is 401
          console.log "Authentication Failed :("
          return

        if response.statusCode isnt 200
          console.log "Request didn't come back HTTP 200 :("
          return

        console.log "Got back #{body}" # for debugging turn off when it works

        robot.messageRoom helpDeskChannel, "New/Open and Unowned tickets: #{body}"
