# Description:
#   In the Help Desk channel the pattern #[0-9]+ should turn into a link to the ticket
#    
#
# Commands:
#   #NUMBER in Help Desk Channel - turns into a link to ticket which would be
#                                  https://help.door43.org/Ticket/Display.html?id=NUMBER

module.exports = (robot) ->

  get_username = (response) ->
    "@#{response.message.user.name}"
    
  get_channel = (response) ->
    if response.message.room == response.message.user.name
      "@#{response.message.room}"
    else
      "##{response.message.room}"

  # listen for a ticket number
  robot.hear /#[0-9]+/g, (response) -> 
    helpDeskChannel = '#helpdesk'
    
    if (get_channel(response) == helpDeskChannel)
      respTktNum = response.match.toString().split('#')[1]
      response.send "https://help.door43.org/Ticket/Display.html?id=#{respTktNum}"