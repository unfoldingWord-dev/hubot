# Description:
#   Logs chat to Redis and displays it over HTTP
#
# Dependencies:
#   "redis": ">=0.7.2"
#   "moment": ">=1.7.0"
#   "connect": ">=2.4.5"
#   "connect_router": "*"
#
# Configuration:
#   LOG_REDIS_URL: URL to Redis backend to use for logging (uses REDISTOGO_URL 
#                  if unset, and localhost:6379 if that is unset.
#   LOG_HTTP_USER: username for viewing logs over HTTP (default 'logs' if unset)
#   LOG_HTTP_PASS: password for viewing logs over HTTP (default 'changeme' if unset)
#   LOG_HTTP_PORT: port for our logging Connect server to listen on (default 8081)
#   LOG_STEALTH:   If set, bot will not announce that it is logging in chat
#   LOG_MESSAGES_ONLY: If set, bot will not log room enter or leave events
#   LOG_CHARSET:   Charset for serving the logs (default 'utf-8' if unset)
#
# Commands:
#   hubot send me today's logs - messages you the logs for today
#   hubot what did I miss - messages you logs for the past 10 minutes
#   hubot what did I miss in the last x seconds/minutes/hours - messages you logs for the past x
#   hubot start logging - start logging messages from now on
#   hubot stop logging  - stop logging messages for the next 15 minutes
#   hubot stop logging forever - stop logging messages indefinitely
#   hubot stop logging for x seconds/minutes/hours - stop logging messages for the next x
#   i request the cone of silence - stop logging for the next 15 minutes
#
# Notes:
#   This script by default starts a Connect server on 8081 with the following routes:
#     /
#       Form that takes a room ID and two UNIX timestamps to show the logs between.
#       Action is a GET with room, start, and end parameters to /logs/view.
#
#     /logs/view?room=room_name&start=1234567890&end=1456789023&presence=true
#       Shows logs between UNIX timestamps <start> and <end> for <room>,
#       and includes presence changes (joins, parts) if <presence>
#
#     /logs/:room
#       Lists all logs in the database for <room>
#
#     /logs/:room/YYYMMDD?presence=true
#       Lists all logs in <room> for the date YYYYMMDD, and includes joins and parts
#       if <presence>
#
#   Feel free to edit the HTML views at the bottom of this module if you want to make the views
#   prettier or more functional.
#
#   I have only thoroughly tested this script with the xmpp and shell adapters. It doesn't use
#   anything that necessarily wouldn't work with other adapters, but it's possible some adapters
#   may have issues sending large amounts of logs in a single message.
#
# Author:
#   jenrzzz


Redis = require "redis"
Url   = require "url"
Util  = require "util"
Connect = require "connect"
Connect.router = require "connect_router"
OS = require "os"
moment = require "moment"
hubot = require "hubot"

# Convenience class to represent a log entry
class Entry
 constructor: (@from, @timestamp, @type='text', @message='') ->

redis_server = Url.parse process.env.LOG_REDIS_URL || process.env.REDISTOGO_URL || 'redis://localhost:6379'

module.exports = (robot) ->
  robot.logging ||= {} # stores some state info that should not persist between application runs
  robot.brain.data.logging ||= {}
  robot.logger.debug "Starting chat logger."

  # Setup our own redis connection
  client = Redis.createClient redis_server.port, redis_server.hostname
  if redis_server.auth
    client.auth redis_server.auth.split(":")[1]
  client.on 'error', (err) ->
    robot.logger.error "Chat logger was unable to connect to a Redis backend at #{redis_server.hostname}:#{redis_server.port}"
    robot.logger.error err
  client.on 'connect', ->
    robot.logger.debug "Chat logger successfully connected to Redis."

  # Add a listener that matches all messages and calls log_message with redis and robot instances and a Response object
  robot.listeners.push new hubot.Listener(robot, ((msg) -> return true), (res) -> log_message(client, robot, res))

  # Override send methods in the Response prototype so that we can log Hubot's replies
  # This is kind of evil, but there doesn't appear to be a better way
  log_response = (room, strings...) ->
    return unless robot.brain.data.logging[room]?.enabled
    for string in strings
      log_entry client, (new Entry(robot.name, Date.now(), 'text', string)), room

  response_orig =
    send: robot.Response.prototype.send
    reply: robot.Response.prototype.reply

  robot.Response.prototype.send = (strings...) ->
    log_response @message.user.room, strings...
    response_orig.send.call @, strings...

  robot.Response.prototype.reply = (strings...) ->
    log_response @message.user.room, strings...
    response_orig.reply.call @, strings...

  ####################
  ## HTTP interface ##
  ####################

  charset = process.env.LOG_CHARSET || 'utf-8'
  if charset?
    charset_parameter = '; charset:' + charset
    charset_meta = '<meta charset="utf-8" />'
  else
    charset_parameter = charset_meta = ''

  connect = Connect()
  #connect.use Connect.basicAuth(process.env.LOG_HTTP_USER || 'logs', process.env.LOG_HTTP_PASS || 'changeme')
  connect.use Connect.bodyParser()
  connect.use Connect.query()
  connect.use Connect.router (app) ->
    app.get '/', (req, res) ->
      res.statusCode = 200
      res.setHeader 'Content-Type', 'text/html' + charset_parameter
      res.end views.index(charset_meta: charset_meta)

    app.get '/logs', (req, res) ->
      res.statusCode = 200
      res.setHeader 'Content-Type', 'text/html' + charset_parameter
      
      res.write views.log_view.head(charset_meta: charset_meta)
      res.write """
              <div style="vertical-align:middle">
                <img src="https://a.slack-edge.com/f30f/img/services/api_200.png" style="width:100px;"><h1 style="display:inline-block;">Team43 Slack Logs</h1>
              </div>
              <form id="search-form" action="/logs/search" method="get">
              <legend>Search the logs</legend>
              <fieldset>
                <div style="float:left; padding-right:10px;">
                  <label for="room">Channel:</label>
                  #<select id="room-select" name="room">
                  <option value="">All Channels</option>
"""
      client.smembers "rooms", (err, rooms) ->
        rooms.sort().forEach (room) ->
          res.write "<option value=\"#{encodeURIComponent(room)}\">#{room}</option>"
        res.write """"
                      </select>
                </div>
                <div float="left;">
                      <label for="search">Text to search:</label>
                      <input id="search" name="search" type="text" maxlength="200" placeholder="Search"/>
                </div>
                <div style="clear:left;float:left; padding-right:10px;">
                      <label for="start">Date: Between</label>
                      <input id="start-date" name="start" type="text" placeholder="mm/dd/yyyy" class="datepicker"/>
                      and <input id="end-date" name="end" type="text" placeholder="mm/dd/yyyy"  class="datepicker"/>
                </div>
                <div style="clear:left;float:left; padding-right:10px;">
                     <label for="from">Author:</label>
                    <input name="from" type="text" maxlength="50"/>
                </div>
                <div style="float:left; padding-right:10px;">
                      <label for="to">Receipiant:</label>
                      @<input name="to" type="text" maxlength="50"/>
                </div>
                <label style="clear:both; white-space: nowrap;" for="raw"><input type="checkbox" name="raw"/> raw</label>
                </fieldset>
                <input type="submit" value="Search"/>
              </form>
"""
        res.write "<legend>View Log by Date</legend>\r\n"
        res.write "<ul>\r\n"

        client.smembers "rooms", (err, rooms) ->
          rooms.sort().forEach (room) ->
            res.write "<li><a href=\"/logs/#{encodeURIComponent(room)}\">##{room}</a></li>\r\n"
          res.write "</ul>"
          res.end views.log_view.tail

    app.get '/logs/view', (req, res) ->
      res.statusCode = 200
      res.setHeader 'Content-Type', 'text/html' + charset_parameter
      if not (req.query.start && req.query.end)
        res.end '<strong>No start or end date provided</strong>'
      m_start = parseInt(req.query.start)
      m_end   = parseInt(req.query.end)
      if isNaN(m_start) or isNaN(m_end)
        res.end "Invalid range"
        return
      m_start = moment.unix m_start
      m_end   = moment.unix m_end
      room = req.query.room || 'general'
      presence = !!req.query.presence
      get_logs_for_range client, m_start, m_end, room, (replies) ->
        res.write views.log_view.head(charset_meta: charset_meta)
        res.write format_logs_for_html(replies, room, presence).join("\r\n")
        res.end views.log_view.tail

    app.get '/logs/search', (req, res) ->
      res.statusCode = 200
      res.setHeader 'Content-Type', 'text/html' + charset_parameter
      start = req.query.start || ''
      end   = req.query.end || ''
      room = req.query.room || ''
      search = req.query.search || ''
      to = req.query.to || ''
      from = req.query.from || ''
      raw = req.query.raw || false
      earliest_date = moment('07/22/2015')
      latest_date = moment()
      if(! start)
        m_start = earliest_date.clone()
      else
        m_start = moment(start)
        if not m_start.isValid()
          m_start = earliest_date.clone()
        if m_start.diff(earliest_date) < 0
          m_start = earliest_date.clone()
        if m_start.diff(latest_date) > 0
          m_start = latest_date.clone()
        start = m_start.format('MM/DD/YYYY')

      if(! end)
        m_end = latest_date.clone()
      else
        m_end = moment(end)
        if not m_end.isValid()
          m_end = latest_date.clone()
        if m_end.diff(m_start) < 0
          m_end = m_start.clone()
        if m_end.diff(latest_date) > 0
          m_end = latest_date.clone()
        if m_end.diff(earliest_date) < 0
          m_end = earliest_date.clone()
        end = m_end.format('MM/DD/YYYY')

      res.write views.log_view.head(charset_meta: charset_meta)
      res.write """
          <form action="/logs/search" class="form-horizontal" method="GET" id="search-form">
            <fieldset>
              <a href="/logs"><img src="https://a.slack-edge.com/f30f/img/services/api_200.png" width="25px"></a>
              <strong>Search</strong>
              #<select id="room-select" name="room" style="width:150px" class="submit-on-change">
                <option value="">All Channels</option>
"""
      client.smembers "rooms", (err, rooms) ->
        rooms.sort().forEach (r) ->
          res.write "<option value=\"#{encodeURIComponent(r)}\"#{if room and room==r then 'selected="selected"' else ''}>#{r}</option>"
        res.write """"
              </select>
              for <input id="search" name="search" type="text" maxlength="150" placeholder="Text to search" value="#{search}" style="width:200px"/>
              Between <input id="start-date" name="start" type="text" placeholder="mm/dd/yyyy" class="datepicker" value="#{start}" style="width:75px"/>
              -
              <input id="end-date" name="end" type="text" placeholder="mm/dd/yyyy"  class="datepicker" value="#{end}" style="width:75px"/>
              @<input name="from" type="text" placeholder="Author" value="#{from}" style="width:75px"/>
              @<input name="to" type="text" placeholder="Receipiant" value="#{to}" style="width:75px"/>
              <label style="white-space: nowrap;display:inline-block" for="raw"><input type="checkbox" name="raw" value="true"#{if raw then ' checked="checked"' else ''}/> raw</label>
              <input type="submit" value="Search"/>
            </fieldset>
          </form>
        """

        if not room and not search and not from and not to and not start
          res.write """
                   <div class="no-results">Please select a channel, enter a search term, or select a start date</div>
            """
          res.end views.log_view.tail
          return

      search_logs_for_array client, room, enumerate_keys_for_date_range(m_start, m_end), search, to, from, (replies) ->
        if not replies or not replies.length
          res.write """
                 <div class="no-results">No results found</div>
          """
        else
          res.write '<div style="font-style:italic;text-align:right;">* Note: All times are in UTC/GMT, 4 hours ahead of EST</div>'
          res.write format_logs_for_html(replies, room, true, search, raw).join("\r\n")
        res.end views.log_view.tail

    app.get '/logs/:room', (req, res) ->
      res.statusCode = 200
      res.setHeader 'Content-Type', 'text/html' + charset_parameter
      res.write views.log_view.head(charset_meta: charset_meta)
      res.write "<h2>Logs for #{req.params.room}</h2>\r\n"
      res.write "<ul>\r\n"

      res.write "<li><a href=\"/logs/search?room=#{encodeURIComponent(req.params.room)}\">All Dates</a></li>\r\n"

      # This is a bit of a hack... KEYS takes O(n) time
      # and shouldn't be used for this, but it's not worth
      # creating a set just so that we can list all logs 
      # for a room.
      client.keys "logs:#{req.params.room}:*", (err, replies) ->
        days = []
        for key in replies
          key = key.slice key.lastIndexOf(':')+1, key.length
          days.push moment(key, "YYYYMMDD")
        days.sort (a, b) ->
            return b.diff(a)
        days.forEach (date) ->
          res.write "<li><a href=\"/logs/search?room=#{encodeURIComponent(req.params.room)}&start=#{date.format('MM/DD/YYYY')}&end=#{date.format('MM/DD/YYYY')}\">#{date.format('dddd, MMMM Do YYYY')}</a></li>\r\n"
        res.write "</ul>"
        res.end views.log_view.tail

    app.get '/logs/:room/:id', (req, res) ->
      res.statusCode = 200
      res.setHeader 'Content-Type', 'text/html' + charset_parameter
      presence = !!req.query.presence
      id = parseInt req.params.id
      if isNaN(id)
        res.end "Bad log ID"
        return
      get_log client, req.params.room, id, (logs) ->
        res.write views.log_view.head(charset_meta: charset_meta)
        res.write format_logs_for_html(logs, req.params.room, presence).join("\r\n")
        res.end views.log_view.tail

  robot.log_server = connect.listen process.env.LOG_HTTP_PORT || 8081

  ####################
  ## Chat interface ##
  ####################

  # When we join a room, wait for some activity and notify that we're logging chat
  # unless we're in stealth mode
  robot.hear /.*/, (msg) ->
    room = msg.message.user.room
    robot.logging[room] ||= {}
    enabled = true
    if robot.adapter.client and robot.adapter.client.groups
      for group in robot.adapter.client.groups
        if group.name == room
          enabled = false  # Do not log private groups by default
          break 
    robot.brain.data.logging[room] ||= {'enabled': enabled}
    if msg.match[0].match(///(#{robot.name} )?(start|stop) logging*///) or process.env.LOG_STEALTH
      robot.logging[room].notified = true
      return
    if robot.brain.data.logging[room].enabled and not robot.logging[room].notified
      #msg.send "I'm logging messages in #{room} at " +
      #          "http://#{OS.hostname()}:#{process.env.LOG_HTTP_PORT || 8081}/" +
      #          "logs/#{encodeURIComponent(room)}/#{date_id()}\n" +
      #          "Say `#{robot.name} stop logging forever' to disable logging indefinitely."
      robot.logging[room].notified = true

  # Enable logging
  robot.respond /start logging( messages)?$/i, (msg) ->
    enable_logging robot, client, msg

  # Disable logging with various options
  robot.respond /stop logging( messages)?$/i, (msg) ->
    end = moment().add('minutes', 15)
    disable_logging robot, client, msg, end

  robot.respond /stop logging forever$/i, (msg) ->
    disable_logging robot, client, msg, 0

  robot.hear /requests? the cone of silence/i, (msg) ->
    end = moment().add('minutes', 15)
    disable_logging robot, client, msg, end

  robot.respond /stop logging( messages)? for( the next)? ([0-9]+) (seconds?|minutes?|hours?)$/i, (msg) ->
    num = parseInt msg.match[3]
    return if isNaN(num)
    end = moment().add(msg.match[4][0], num)
    disable_logging robot, client, msg, end

  # PM logs to people who request them
  robot.respond /(message|send) me (all|the|today'?s) logs?$/i, (msg) ->
    get_logs_for_day client, new Date(), msg.message.user.room, (logs) ->
      if logs.length == 0
        msg.reply "I don't have any logs saved for today."
        return

      logs_formatted = format_logs_for_chat(logs)
      robot.send direct_user(msg.message.user.id, msg.message.user.room), logs_formatted.join("\n")

  robot.respond /what did I miss\??$/i, (msg) ->
    now = moment()
    before = moment().subtract('m', 10)
    get_logs_for_range client, before, now, msg.message.user.room, (logs) ->
      logs_formatted = format_logs_for_chat(logs)
      robot.send direct_user(msg.message.user.id, msg.message.user.room), logs_formatted.join("\n")

  robot.respond /what did I miss in the [pl]ast ([0-9]+) (seconds?|minutes?|hours?)\??/i, (msg) ->
    num = parseInt(msg.match[1])
    if isNaN(num)
      msg.reply "I'm not sure how much time #{msg.match[1]} #{msg.match[2]} refers to."
      return
    now   = moment()
    start = moment().subtract(msg.match[2][0], num)

    if now.diff(start, 'days', true) > 1
      robot.send direct_user(msg.message.user.id, msg.message.user.room),
                 "I can only tell you activity for the last 24 hours in a message."
      start = now.sod().subtract('d', 1)

    get_logs_for_range client, start, moment(), msg.message.user.room, (logs) ->
      logs_formatted = format_logs_for_chat(logs)
      robot.send direct_user(msg.message.user.id, msg.message.user.room), logs_formatted.join("\n")


####################
##    Helpers     ##
####################

# Converts date into a string formatted YYYYMMDD
date_id = (date=moment())->
  date = moment(date) if date instanceof Date
  return date.format("YYYYMMDD")

# Returns an array of date IDs for the range between
# start and end (inclusive)
enumerate_keys_for_date_range = (start, end) ->
  ids = []
  start = moment(start) if start instanceof Date
  end = moment(end) if end instanceof Date
  start_i = moment(start)
  while end.diff(start_i, 'days', true) >= 0
    ids.push date_id(start_i)
    start_i.add 'days', 1
  return ids

# Returns an array of pretty-printed log messages for <logs>
# Params:
#   logs - an array of log objects
format_logs_for_chat = (logs) ->
  formatted = []
  logs.forEach (item) ->
    entry = JSON.parse item
    timestamp = moment(entry.timestamp)
    str = timestamp.format("MMM DD YYYY HH:mm:ss")

    if entry.type is 'join'
      str += " #{entry.from} joined"
    else if entry.type is 'part'
      str += " #{entry.from} left"
    else
      str += " <#{entry.from}> #{entry.message}"
    formatted.push str
  return formatted

# Returns an array of lines representing a table for <logs>
# Params:
#   logs - an array of log objects
format_logs_for_html = (logs, room, presence=true, search=null, raw=false) ->
  lines = []
  last_entry = null
  last_room = null
  if raw
    lines.push """<table class="span12" cellspacing=0 cellpadding=5>\n"""
  for l in logs
    # Don't print a bunch of join or part messages for the same person. Hubot sometimes
    # sees keepalives from Jabber gateways as multiple joins
    continue if l.type != 'text' and l.from == last_entry?.from and l.type == last_entry?.type
    continue if not presence and l.type != 'text'
    continue if l.from == 'unknown'
    l.date = moment(l.timestamp)

    # If the date changed
    if not raw
      if not (l.room == last_room and l.date.date() == last_entry?.date?.date() and l.date.month() == last_entry?.date?.month())
        lines.push """
                  <div class="row logentry">
                    <div class="span12" style="text-align:center;margin:20px 0;">
                      <div class="day_divider" data-date="#{l.room}-#{l.date.format("YYYY-MM-DD")}"><i class="copy_only"><br>----- </i><div class="day_divider_label" aria-label="#{l.date.format("MMMM D, YYYY")}">#{l.date.format("MMMM D, YYYY")}#{if ! room then ' #'+l.room else ''}</div><i class="copy_only"> #{l.date.format("MMMM D, YYYY")}#{if ! room then ' #'+l.room else ''} -----</i></div>
                      <div class="line" style="margin: -18px 0 0;;border-top: 1px solid #e8e8e8;"></div>
                    </div>
                  </div>
                """
      last_entry = l
      last_room = l.room

    l.time = moment(l.timestamp).format("h:mm:ss a")
    charIndex = ''+(l.from.toUpperCase().charCodeAt(0) - 'A'.charCodeAt(0))
    if(charIndex == '21')
      charIndex = '23'
    if(charIndex.length == 1)
      charIndex = '0'+charIndex
    avatar = 'https://i1.wp.com/a.slack-edge.com/66f9/img/avatars/ava_00'+charIndex+'-48.png'
    switch l.type
      when 'join'
        if not raw
          message = '<span class="status-message">joined #'+escapeHTML(l.room)+'.</span>'
        else
          message = 'joined #'+escapeHTML(l.room)+'.'
      when 'part'
        if not raw
          message = '<span class="status-message">left '+escapeHTML(l.room)+'</span>'
        else
          message = 'left #'+escapeHTML(l.room)+'.'
      when 'text'
        message = escapeHTML(l.message)
        message = message.replace /\b(?!git@)(\w)[^\s]+@\S+(\.[^\s.]+)/g, "$1***@****$2"
        if not raw
          if(search)
            re = new RegExp('('+search+')', 'gi')
            message = message.replace re, '<span style="font-weight:bold;font-style:italic;color:green;"><i>$1</i></span>'
          message = message.replace /and commented:\s+([\S\n\s]+)$/i, 'and commented:<br/><code>$1</code>'
          message = message.replace /```\n*((.|\n)+?)```/gm, '<br/><pre style="background-color=#efefef">$1</pre>'
          message = message.replace /\n/gm, '<br/>'
          message = message.replace /(^|\s)@([\w\.-]+)/g, '$1<span style="font-weight:bold;font-style:italic">@$2</span>'
          message = message.replace /(^|\b)(https{0,1}:\/\/[\w\/\._:\?=\&\%\;\#~-]+)(\b|$)/, '<a href="$2" target="_blank">$2</a>'
          message = message.replace />(https{0,1}:\/\/(?!team43.slack.com)[\w\/\._:\?=\&\%\;\#-]+\.(gif|jpg|jpeg|png))</i, '><img src="$1" style="max-height:300px;max-width=600px;"><'
          message = message.replace /:stuck_out_tongue:/g, '<span class="emoji-outer emoji-sizer emoji-only"><span class="emoji-inner" style="background: url(https://a.slack-edge.com/e4cee/img/emoji_2016_02_06/sheet_apple_64_indexed_256colors.png);background-position:67.5% 0%;background-size:4100%" title="stuck_out_tongue">:stuck_out_tongue:</span></span>'
          message = message.replace /:wink:/g, '<span class="emoji-outer emoji-sizer emoji-only"><span class="emoji-inner" style="background: url(https://a.slack-edge.com/e4cee/img/emoji_2016_02_06/sheet_apple_64_indexed_256colors.png);background-position:65% 57.5%;background-size:4100%" title="wink">:wink:</span></span>'
          message = message.replace /:simple_smile:/g, '<span class="emoji emoji-sizer emoji-only" style="background-image:url(https://a.slack-edge.com/66f9/img/emoji_2015/apple-old/simple_smile.png)" title="simple_smile">:simple_smile:</span>'
          message = message.replace /:laughing:/g, '<span class="emoji-outer emoji-sizer emoji-only"><span class="emoji-inner" style="background: url(https://a.slack-edge.com/e4cee/img/emoji_2016_02_06/sheet_apple_64_indexed_256colors.png);background-position:65% 50%;background-size:4100%" title="laughing">:laughing:</span></span>'
          message = message.replace /:smile:/g, '<span class="emoji-outer emoji-sizer emoji-only"><span class="emoji-inner" style="background: url(https://a.slack-edge.com/e4cee/img/emoji_2016_02_06/sheet_apple_64_indexed_256colors.png);background-position:65% 45%;background-size:4100%" title="smile">:smile:</span></span>'
          message = message.replace /:\+1:/g, '<span class="emoji-outer emoji-sizer emoji-only"><span class="emoji-inner" style="background: url(https://a.slack-edge.com/e4cee/img/emoji_2016_02_06/sheet_apple_64_indexed_256colors.png);background-position:37.5% 20%;background-size:4100%" title="+1">:+1:</span></span>'
          message = message.replace /:-1:/g, '<span class="emoji-outer emoji-sizer emoji-only"><span class="emoji-inner" style="background: url(https://a.slack-edge.com/e4cee/img/emoji_2016_02_06/sheet_apple_64_indexed_256colors.png);background-position:37.5% 35%;background-size:4100%" title="-1">:-1:</span></span>'
          message = message.replace /:stuck_out_tongue_winking_eye:/g, '<span class="emoji-outer emoji-sizer emoji-only"><span class="emoji-inner" style="background: url(https://a.slack-edge.com/e4cee/img/emoji_2016_02_06/sheet_apple_64_indexed_256colors.png);background-position:67.5% 2.5%;background-size:4100%" title="stuck_out_tongue_winking_eye">:stuck_out_tongue_winking_eye:</span></span>'
          message = message.replace /:clap:/g, '<span class="emoji-outer emoji-sizer emoji-only"><span class="emoji-inner" style="background: url(https://a.slack-edge.com/e4cee/img/emoji_2016_02_06/sheet_apple_64_indexed_256colors.png);background-position:37.5% 50%;background-size:4100%" title="clap">:clap:</span></span>'
          message = message.replace /:smiley:/g, '<span class="emoji-outer emoji-sizer emoji-only"><span class="emoji-inner" style="background: url(https://a.slack-edge.com/e4cee/img/emoji_2016_02_06/sheet_apple_64_indexed_256colors.png);background-position:65% 42.5%;background-size:4100%" title="smiley">:smiley:</span></span>'
    if not raw
      lines.push """<div class="row logentry" id="#{l.room}-#{l.from}-#{l.timestamp}">
                    <div class="span1" style="text-align:right;">
                      <img src="#{avatar}"/>
                    </div>
                    <div class="span11" style="margin-left: 10px">
                      <div class="name-and-time"><a href="https://team43.slack.com/team/#{escapeHTML(l.from)}" target="_blank" class="log-from">#{escapeHTML(l.from)}</a> <a class="log-time" href="/logs/search?room=#{escapeHTML(l.room)}&start=#{l.date.clone().subtract('days',1).format('MM/DD/YYYY')}&end=#{l.date.clone().add('days',7).format('MM/DD/YYYY')}##{escapeHTML(l.room+'-'+l.from+'-'+l.timestamp)}">#{l.time.toUpperCase()}</a></div>
                      <div class="log-message">#{message}</div>
                    </div>
                  </div>
               """
    else
#      lines.push """<div class="row logentry" id="#{l.room}-#{l.from}-#{l.timestamp}">
#                      <div class="span2 log-time" style="margin:0 !important"><a class="log-time" href="/logs/search?room=#{escapeHTML(l.room)}&start=#{l.date.clone().subtract('days',1).format('MM/DD/YYYY')}&end=#{l.date.clone().add('days',7).format('MM/DD/YYYY')}&raw=true##{escapeHTML(l.room+'-'+l.from+'-'+l.timestamp)}">#{l.date.format("YYYY-MM-DD HH:mm:ss")}</a></div>
#      """
#      if ! room
#        lines.push """<div class="span2 log-room" style="margin:0 !important">##{l.room}</div>"""
#      lines.push """  <div class="span2 log-from" style="margin:0 !important">#{l.from}</div>
#                      <div class="span#{if room then "9" else "7"} log-message">#{message}</div>
#                    </div>
#                """
      lines.push """<tr class="row logentry-raw" id="#{l.room}-#{l.from}-#{l.timestamp}">
                      <td class="log-time-raw" style="width:1%;white-space:nowrap;vertical-align:top;text-align:left;"><a class="log-time" href="/logs/search?room=#{escapeHTML(l.room)}&start=#{l.date.clone().subtract('days',1).format('MM/DD/YYYY')}&end=#{l.date.clone().add('days',7).format('MM/DD/YYYY')}&raw=true##{escapeHTML(l.room+'-'+l.from+'-'+l.timestamp)}">#{l.date.format("YYYY-MM-DD HH:mm:ss")}</a></td>
      """
      if ! room
        lines.push """<td class="log-room-raw" style="width:1%;white-space:nowrap;vertical-align:tope;text-align:left;">##{l.room}</td>"""
      lines.push """  <td class="log-from-raw" style="width:1%;white-space:nowrap;vertical-align:top;text-align:left;">#{l.from}</td>
                      <td class=log-message-raw" style="vertical-align:top;text-align:left;">#{message}</td>
                    </tr>
                """
  if raw
    lines.push """</table>"""

  return lines

# Returns a User object to send a direct message to
# Params:
#   id   - the user's adapter ID
#   room - string representing the room the user is in (optional for some adapters)
direct_user = (id, room=null) ->
  u =
    type: 'direct'
    id: id
    room: room

# Calls back an array of JSON log objects representing the log
# for the given ID
# Params:
#   redis - a Redis client object
#   room  - the room to look up logs for
#   id    - the date to look up logs for
#   callback - a function that takes an array
get_log = (redis, room, id, callback) ->
  log_key = "logs:#{room}:#{id}"
  return [] if not redis.exists log_key
  redis.lrange [log_key, 0, -1], (err, replies) ->
    results = []
    for rep in replies
      try
        json = JSON.parse rep
        json['room'] = room
        results.push json
      catch e
    callback(results)

# Calls back an array of JSON log objects representing the log
# for every date ID in <ids>
# Params:
#   redis - a Redis client object
#   room  - the room to look up logs for
#   ids   - an array of YYYYMMDD date id strings to pull logs for
#   callback - a function taking an array of log objects
get_logs_for_array = (redis, room, ids, callback) ->
    results = []
    m = redis.multi()
    for id in ids
      m.lrange("logs:#{r}:#{id}", 0, -1)
      m.exec (err, reply) ->
        if reply[0] instanceof Array
          for rep in reply[0]
            try
              json = JSON.parse rep
              json['room'] = room
              results.push json
            catch e
        else
          try
            json = JSON.parse reply
            json['room'] = room
            results.push json
          catch e
        callback(results)

search_logs_for_array = (redis, room, ids, search, to, from, callback) ->
  redis.smembers "rooms", (err, rooms) ->
    if room and rooms.indexOf(room) < 0
      callback([])
      return
    results = []
    callsRemaining = 0
    for id in ids
      do(id)->
        for r in rooms.sort()
          if ! room or r == room
            do(r)->
              ++callsRemaining
              m = redis.multi()
              m.lrange("logs:#{r}:#{id}", 0, -1)
              m.exec (err, reply) ->
                if reply[0] instanceof Array
                  reply[0].forEach (rep, i) ->
                    if rep and rep != '' and (i == 0 or (i > 0 and reply[0][i-1] != reply[0][i]))
                      try
                        json = JSON.parse rep
                        if (search and json.message.toLowerCase().indexOf(search.toLowerCase()) <0) or (to and json.message.indexOf('@'+to) < 0) or (from and json.from != from)
                          return
                        json['room'] = r
                        results.push json
                      catch e
                else
                  try
                    json = JSON.parse reply
                    json['room'] = room
                    results.push json
                  catch e
                --callsRemaining
                if callsRemaining <= 0
                  callback(results)

# Calls back an array of JSON log objects representing the log
# for <date>
# Params:
#   redis - a Redis client object
#   date  - Date or Moment object representing the date to look up
#   room  - the room to look up 
#   callback - function to pass an array of log objects for date to
get_logs_for_day = (redis, date, room, callback) ->
  get_log redis, room, date_id(date), (reply) ->
    callback(reply)

# Calls back an array of JSON log objects representing the log
# between <start> and <end>
# Params:
#   redis  - a Redis client object
#   start  - Date or Moment object representing the start of the range
#   end    - Date or Moment object representing the end of the range (inclusive)
#   room   - the room to look up logs for
#   callback - a function taking an array as an argument
get_logs_for_range = (redis, start, end, room, callback) ->
  get_logs_for_array redis, room, enumerate_keys_for_date_range(start, end), (logs) ->
    # TODO: use a fuzzy binary search to find the start and end indices
    # of the log entries we want instead of iterating through the whole thing
    slice = []
    for log in logs
      e = JSON.parse log
      slice.push e if e.timestamp >= start.valueOf() && e.timestamp <= end.valueOf()
    callback(slice)

# Enables logging for the room that sent response
# Params:
#   robot - a Robot instance
#   redis - a Redis client object
#   response - a Response that can be replied to
enable_logging = (robot, redis, response) ->
  robot.brain.data.logging[response.message.user.room] ||= {}
  if robot.brain.data.logging[response.message.user.room].enabled
    response.reply "Logging is already enabled."
    return
  robot.brain.data.logging[response.message.user.room].enabled = true
  robot.brain.data.logging[response.message.user.room].pause = null
  log_entry(redis, new Entry(robot.name, Date.now(), 'text',
            "#{response.message.user.name || response.message.user.id} restarted logging."),
            response.message.user.room)

  # Fall back to user name if no room, or "Unknown"
  room = response.message.user.room || response.message.user.name || response.message.user.id || "Unknown"
  response.reply "I will log messages in #{room} at " +
                 "http://#{OS.hostname()}:#{process.env.LOG_HTTP_PORT || 8081}/" +
                 "logs/#{encodeURIComponent(room)}/#{date_id()} from now on.\n" +
                 "Say `#{robot.name} stop logging forever' to disable logging indefinitely."
  robot.brain.save()

# Disables logging for the room that sent response
# Params:
#   robot - a Robot instance
#   redis - a Redis client object
#   response - a Response that can be replied to
#   end - a Moment representing the time at which to start logging again, or
#       - a number representing the number of milliseconds until logging should be resumed, or
#       - 0 or undefined to disable logging indefinitely
disable_logging = (robot, redis, response, end=0) ->
  room = response.message.user.room
  robot.brain.data.logging[room] ||= {'enabled':true}

  # If logging was already disabled
  if robot.brain.data.logging[room].enabled == false
    if robot.brain.data.logging[room].pause
      pause = robot.brain.data.logging[room].pause
      if pause.time and pause.end and end and end != 0
        response.reply "Logging was already disabled #{pause.time.fromNow()} by " +
                       "#{pause.user} until #{pause.end.format()}."
      else
        robot.brain.data.logging[room].pause = null
        response.reply "Logging is currently disabled."
    else
      response.reply "Logging is currently disabled."
    return

  # Otherwise, disable it
  robot.brain.data.logging[room].enabled = false
  if end != 0
    if not end instanceof moment
      if end instanceof Date
        end = moment(end)
      else
        end = moment().add('seconds', parseInt(end))
    robot.brain.data.logging[room].pause =
      time: moment()
      user: response.message.user.name || response.message.user.id || 'unknown'
      end: end
    log_entry(redis, new Entry(robot.name, Date.now(), 'text',
              "#{response.message.user.name || response.message.user.id} disabled logging" +
              " until #{end.format()}."), room)

    # Re-enable logging after the set amount of time
    setTimeout (-> enable_logging(robot, redis, response) if not robot.brain.data.logging[room].enabled),
                  end.diff(moment())
    response.reply "OK, I'll stop logging until #{end.format()}."
    robot.brain.save()
    return
  log_entry(redis, new Entry(robot.name, Date.now(), 'text',
            "#{response.message.user.name || response.message.user.id} disabled logging indefinitely."), 
            room)

  robot.brain.save()
  response.reply "OK, I'll stop logging from now on."

# Logs an Entry object
# Params:
#   redis - a Redis client instance
#   entry - an Entry object to log
#   room  - the room to log it in
log_entry = (redis, entry, room='general') ->
  if not entry.type && entry.timestamp
    throw new Error("Argument #{entry} to log_entry is not an entry object")
  entry = JSON.stringify entry
  redis.rpush("logs:#{room}:#{date_id()}", entry)
  redis.sadd("rooms", room)

# Listener callback to log message in redis
# Params:
#   redis - a Redis client instance
#   response - a Response object emitted from a Listener
log_message = (redis, robot, response) ->
  return if not robot.brain.data.logging[response.message.user.room]?.enabled
  if response.message instanceof hubot.TextMessage
    type = 'text'
  else if response.message instanceof hubot.EnterMessage
    type = 'join'
  else if response.message instanceof hubot.LeaveMessage
    type = 'part'
  return if process.env.LOG_MESSAGES_ONLY && type != 'text'
  entry = JSON.stringify(new Entry(response.message.user.name || response.message.user.id || 'unknown', Date.now(), type, response.message.text))
  room = response.message.user.room || 'general'
  redis.rpush("logs:#{room}:#{date_id()}", entry)
  redis.sadd("rooms", room)

escapeHTML = (str) ->
  if toString.call(str) == '[object String]'
    str = str.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  str
####################
##     Views      ##
####################

views =
  index: (context) -> """
<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
  <html lang="en-US">
      <head profile="http://www.w3.org/2005/10/profile">
        <link rel="icon" type="image/png" href="https://a.slack-edge.com/f30f/img/services/api_200.png">
        #{ context.charset_meta }
        <title>View logs</title>
        <link href="//netdna.bootstrapcdn.com/twitter-bootstrap/2.1.1/css/bootstrap-combined.min.css" rel="stylesheet">
      </head>
      <body>
        <div class="container">
          <div class="row">
            <div class="span8">
              <h1>&nbsp;</h1>
              <h2><a href="/logs">Browse all rooms</a></h2>
<!--
              <h1>&nbsp;</h1>
              <form action="/logs/view" class="form-vertical" method="get">
              <fieldset>
                <legend>Search for logs</legend>
                <label for="room">JID of room</label>
                <input name="room" type="text" placeholder="chatroom@conference.jabber.example.com"><br />
                <label for="start">UNIX timestamp for start date</label>
                <input name="start" type="text" placeholder="1234567890" />
                <label for="end">End date</label>
                <input name="end" type="text" placeholder="1234567890" />
                <span><label for="presence">Show joins and parts?</label>
                <input name="presence" type="checkbox" /></span><br /><br />
                <button type="submit" class="btn">Submit</button>
              </fieldset>
              </form>
-->
            </div>
          </div>
        </div>
      </body>
    </html>"""

  log_view:
    head: (context) -> """
<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
  <html lang="en-US">
      <head profile="http://www.w3.org/2005/10/profile">
          <link rel="icon" type="image/png" href="https://a.slack-edge.com/f30f/img/services/api_200.png">
          #{ context.charset_meta }
          <title>Viewing logs</title>
          <link href="//netdna.bootstrapcdn.com/twitter-bootstrap/2.1.1/css/bootstrap-combined.min.css" rel="stylesheet">
          <link rel="stylesheet" href="//code.jquery.com/ui/1.11.4/themes/smoothness/jquery-ui.css">
          <script src="//code.jquery.com/jquery-1.10.2.js"></script>
          <script src="//code.jquery.com/ui/1.11.4/jquery-ui.js"></script>
          <style type="text/css">
            .logentry {
/*              font-family: Consolas, Inconsolata, monospace;*/
              font-family: Slack-Lato,appleLogo,sans-serif;
              margin-top: 10px;
            }
            .username {
              color: blue;
              font-weight: bold;
            }
            .day_divider {
              margin:0;
              background:0 0;
              pointer-events:none;
              padding:0;
              font-size:.9rem;
              line-height:1rem;
              font-family:Slack-Lato,appleLogo,sans-serif;
              color:#2c2d30;
              font-weight:700;
              text-align:center;
              cursor:default;
              clear:both;
              position:relative;
              box-sizing:border-box;              
            }
            .day_divider_label {
              top:-6px;
              border-radius:1rem;
              background:#fff;
              padding:.25rem .75rem;
              display:inline-block;
              margin:0 auto;
              position:relative;
            }
            .copy_only {
              display:inline-block;
              vertical-align:baseline;
              width:1px;
              height:0;
              background-size:0;
              background-repeat:no-repeat;
              font-size:0;
              color:transparent;
              float:left;
              text-rendering:auto;
              -webkit-user-select:none;
            }
            .log-from {
              font-weight: 900;
              color: #2c2d30! important;
              line-height: 1.125rem;
              margin-right: .25rem;
              display: inline;
              word-break: break-word;
            }
            .log-time {
              color: #9e9ea6;
              font-size: 0.75rem;
            }
            .log-room {
              font-weight: bold;
            }
            .log-from {
              font-weight: bold;
            }
            .status-message {
              color:#9e9ea6;
              font-style: italic;
            }
            .no-results {
              margin: 2rem 1rem;
              font-size: 1rem;
              line-height: 1.25rem;
              font-family: Slack-Lato,appleLogo,sans-serif;
              text-align: center;
              color: #9e9ea6;
            }

span.emoji-sizer.emoji-only, span.emoji-sizer {
    line-height: 1.125rem;
    font-size: 1.375rem;
    vertical-align: middle;
    margin-top: -4px;
}
span.emoji-outer {
    display: -moz-inline-box;
    display: inline-block;
    height: 1em;
    width: 1em;
    mmargin-top: -1px;
}
.emoji-only {
    line-height: 2rem;
    font-size: 2rem;
    margin-top: 2px;
}

span.emoji {
    -moz-box-orient: vertical;
    display: inline-block;
    overflow: hidden;
    width: 1em;
    height: 1em;
    background-size: contain;
    background-repeat: no-repeat;
    background-position: 50% 50%;
    text-align: left;
}
span.emoji-sizer.emoji-only, span.emoji-sizer {
    line-height: 1.125rem;
    font-size: 1.375rem;
    vertical-align: middle;
    margin-top: -4px;
}
span.emoji-inner {
    display: -moz-inline-box;
    display: inline-block;
    overflow: hidden;
    width: 100%;
    height: 100%;
    background-size: 4100%!important;
}
span.emoji-inner:not(:empty), span.emoji:not(:empty) {
    text-indent: 100%;
    color: transparent;
    text-shadow: none;
}
.emoji-only {
    line-height: 2rem;
    font-size: 2rem;
    margin-top: 2px;
}


          </style>
          <script>
            $(function() {
              $(".datepicker").datepicker({minDate: new Date(2015, 06, 22), maxDate: new Date()});
            });
          </script>
        </head>
        <body>
          <div class="container">
        """
    tail: "</div></body></html>"
