###
 Description:
   Defines periodic executions
###

module.exports = (robot) ->
  cronJob = require('cron').CronJob

  # runs everyday, do we want this to only run every weekday?
  # every hour post new unowned tickets
  new cronJob('0 0 * * * *', postNewUnownedTickets, null, true)

  postNewUnownedTickets = ->
  	robot.respond (msg) ->
  	  msg.send "Cron: telling slave to check for new tickets", ->
        robot.emit 'slave:newTicket'
        