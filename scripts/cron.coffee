###
 Description:
   Defines periodic executions
###

module.exports = (robot) ->
  cronJob = require('cron').CronJob

  # runs everyday, do we want this to only run every weekday?
  # every hour post new unowned tickets
  new cronJob('0 0 * * * *', postNewUnownedTickets, null, true)

  robot.respond /new-tickets/g, (msg) ->
    msg.send "Manual: Telling slave to check for new tickets"
    postNewUnownedTickets()

  postNewUnownedTickets = ->
    console.log('Let\'s get new tickets!');
    robot.emit 'slave:newTicket'
        