# Description
#    Learns and sends IR hex codes with Broadlink RM.
#
# Configuration:
#   None
#
# Commands:
#   hubot learn <code> [n-m] [@<room>]    - Learns IR hex code at <room> and names it <code>.
#   hubot send [(<wait>)] <code>[@<room>][(<wait>)]*n ...    - Sends IR hex <code> to <room> in <wait> <n> times.
#   hubot list    - Shows all codes and rooms.
#   hubot delete <code>    - Deletes IR hex <code>.
#   hubot delete @<room>    - Deletes <room>.
#   hubot get <code>    - Shows IR hex code of <code>.
#   hubot get @<room>    - Shows MAC or IP address of <room>.
#   hubot set <code> <hex>    - Names <hex> <code>.
#   hubot set @<room> [<MAC>|<IP>]    - Names MAC or IP address <room>.
#   hubot help    - Shows usage.
#   where
#       <code> ::= [0-9a-z:]+
#       <room> ::= [0-9a-z:]+
#       <MAC>  ::= [0-9a-f:]+
#       <IP>   ::= [0-9.]+
#       <wait> ::= [0-9]+(ms|s|m|h|d|second(s)|minute(s)|hour(s)|day(s)|秒|分|時間|日)
#              - <wait> must be less than or equal to 24 days
#
# Examples:
#   hubot learn light:on                    - Learns IR hex code and names it light:on.
#   hubot send light:on                     - Sends IR hex code of light:on.
#   hubot send tv:off aircon:off light:off  - Sends three codes in turn.
#   hubot learn tv:ch 1-8                   - Learns eight codes tv:ch1, tv:ch2, ..., tv:ch8 in turn.
#   hubot leran aircon:warm 14-30           - Also useful to learn many codes of air conditioner.
#   hubot send (7h) aircon:warm24           - Will sends aircon:warm24 in seven hours.
#   hubot send (7 hours) aircon:warm24
#   hubot send (7時間) aircon:warm24
#   hubot send tv:ch1 (2s) tv:source        - Sends tv:ch1 then sends tv:source in two seconds.
#   hubot send tv:ch1 tv:source*3           - Sends tv:ch1 then sends tv:source three times
#   hubot send tv:ch1 tv:source(2s)*3       - Sends tv:ch1 then sends tv:source three times in two seconds.
#   hubot cancel                            - Cancels all unsent codes.
#   hubot get aircon:warm22                 - Shows IR hex code of aircon:warm22.
#   hubot set aircon:clean 123abc...        - Names IR hex code of aircon:clean 123abc... .
#   hubot set @kitchen 192.168.1.23         - Names IP address 192.168.1.23 kitchen.
#   hubot set @bedroom xx:xx:xx:xx:xx       - Names MAC address xx:xx:xx:xx:xx bedroom.
#   hubot learn light:off @kitchen          - Learns IR hex code of light:on at kitchen.
#   hubot send light:off@kitchen            - Sends IR hex code of light:on at kitchen.
#   hubot send light:off@kitchen light:on@bedroom - Sends light:off at kitchen and light:on at bedroom.
#   hubot delete aircon:clean               - Deletes the code of aircon:clean.
#   hubot list                              - Shows all names of codes and rooms.
#   hubot help                              - Shows usage.
#
# Notes:
#   Tested with Broadlink RM Mini3.
#
# Author:
#   Tak Jaga <tak.jaga@gmail.com>

# Copyright (c) 2017 Tak Jaga
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

'use strict'

module.exports = (robot) ->
    robot.respond ///send(((\s+#{WAIT})?\s+#{CODE_AT_N})+)$///i,     (res) -> sendN  robot, res
    robot.respond ///learn\s+(#{CODE})\s*(#{AT})?$///i,              (res) -> learn1 robot, res
    robot.respond ///learn\s+(#{CODE})\s+#{RANGE}(\s+(#{AT}))?$///i, (res) -> learnN robot, res
    robot.respond ///get\s+(@?#{NAME})$///i,                         (res) -> get    robot, res
    robot.respond ///set\s+(@?#{NAME})\s+(#{HEX_ADDR})$///i,         (res) -> set    robot, res
    robot.respond ///delete\s+(@?#{NAME})$///i,                      (res) -> delet  robot, res
    robot.respond ///cancel$///i,                                    (res) -> cancel robot, res
    robot.respond ///list$///i,                                      (res) -> list   robot, res

NAME      = '[0-9a-z:]+'
CODE      = NAME
AT        = '@' + NAME
RANGE     = '(\\d+)-(\\d+)'
HEX_ADDR  = '[0-9a-f:.]+'
WAIT      = '\\(\\s*(\\d+)\\s*(ms|s|m|h|d|seconds?|minutes?|hours?|days?|秒|分|時間|日)\\s*\\)'
REPEAT    = "(#{WAIT})?\\*(\\d+)"
CODE_AT_N = "#{CODE}(#{AT})?(#{REPEAT})?"

getDevice = require 'homebridge-broadlink-rm/helpers/getDevice'
learnData = require 'homebridge-broadlink-rm/helpers/learnData'

# Commands

sendN = (robot, res) ->
    args  = tokenize res.match[1].toLowerCase()
    codes = parse args
    if ok robot, res, codes
        sendN_ robot, res, codes

tokenize = (str) ->
    re = ///#{WAIT}|#{CODE_AT_N}///g
    m[0] while m = re.exec str

parse = (args) ->
    codes = []
    prev  = undefined
    for a in args
        if a[0] is '('
            m = a.match ///#{WAIT}///
            prev = { wait: Number(m[1]), waitUnit: m[2] }
        else
            m = a.match ///(#{CODE})(#{AT})?(#{REPEAT})?///
            codes = codes.concat mkCodes(prev, m)
            prev = undefined
    codes[0].head = true
    codes

mkCodes = (prev, m) ->
    code      = if prev? then prev else {}
    code.code = m[1]
    code.room = m[2] if m[2]?
    repeat    = m[3]
    return [code] unless repeat?
    replicate code, m

replicate = (code, m) ->
    wait = { wait: Number(m[5]), waitUnit: m[6] } if m[4]?
    n    = Number m[7]
    switch n
        when 0 then code.code = undefined ; [code]
        when 1 then [code]
        else replicateN code, wait, n

replicateN = (code, wait, n) ->
    copy = { code: code.code }
    copy.room = code.room if code.room?
    Object.assign copy, wait
    copies = Array(n - 1).fill copy
    [code].concat copies

ok = (robot, res, codes) ->
    for code in codes
        return false unless okCode   robot, res, code
        return false unless okDevice robot, res, code
        return false unless okWait          res, code
    true

okCode = (robot, res, code) ->
    return true unless code.code?
    hex = getVal robot, code.code
    res.send "ERROR no such code #{code.code}" unless hex?
    hex?

okDevice = (robot, res, code) ->
    host = getVal robot, code.room
    if code.room? and not host?
        res.send "ERROR no such room #{code.room}"
        return false
    device = getDevice { host }
    res.send "ERROR device not found #{host}" unless device?
    device?

okWait = (res, code) ->
    w = waitOf code
    return true unless w?
    p = w.millis <= 24 * DAY
    res.send "ERROR (#{w.string}) too long" unless p
    p

waitOf = (code) ->
    w = code.wait
    if w?
        u = code.waitUnit
        m = w * millisOf u
        s = w + u
        { millis: m, string: s }

millisOf = (unit) ->
    switch unit
        when 'ms'                           then 1
        when 's', 'second', 'seconds', '秒' then SEC
        when 'm', 'minute', 'minutes', '分' then MIN
        when 'h', 'hour',   'hours', '時間' then HOUR
        when 'd', 'day',    'days',    '日' then DAY

SEC  = 1000
MIN  = 60 * SEC
HOUR = 60 * MIN
DAY  = 24 * HOUR

sendN_ = (robot, res, codes) ->
    repeat codes, (code, callback) ->
        send robot, res, code, callback

send = (robot, res, code, callback) ->
    if code.code?
        send_ robot, res, code, callback
    else
        wait         res, code, callback

send_ = (robot, res, code, callback) ->
    hex  = getVal robot, code.code
    host = getVal robot, code.room
    back = (msg) -> res.send msg ; callback()
    if hex?
        device = getDevice { host }
        if device?
            wait res, code, ->
                buffer = new Buffer hex, 'hex'
                device.sendData buffer
                room = if code.room? then code.room else ''
                back "sent #{code.code}#{room}"
        else
            back "ERROR device not found #{host}"
    else
        back "ERROR no such code #{code.code}"

wait = (res, code, callback) ->
    w = waitOf code
    if w?
        res.send "wait #{w.string}"
        wait_ w.millis, callback
    else
        if code.head
            callback()
        else
            wait_ 1000, callback

waiting = new Set

wait_ = (millis, callback) ->
    timer = (flip setTimeout) millis, ->
        callback()
        waiting.delete timer
    waiting.add timer

clearWait = ->
    for timer from waiting
        clearTimeout timer
    waiting.clear()

flip = (f) -> (x, y) ->
    f y, x

cancel = (robot, res) ->
    clearWait()
    res.send "canceled"

repeat = (a, f) ->
    if a.length > 0
        f a[0], ->
            a.shift()
            repeat a, f

learn1 = (robot, res) ->
    code = res.match[1] .toLowerCase()
    room = res.match[2]?.toLowerCase()
    learn robot, res, code, room, (->)

learnN = (robot, res) ->
    code  = res.match[1] .toLowerCase()
    room  = res.match[5]?.toLowerCase()
    start = Number res.match[2]
    stop  = Number res.match[3]
    repeat [start .. stop], (n, callback) ->
        learn robot, res, code + n, room, callback

learn = (robot, res, code, room, callback) ->
    hex  = undefined
    host = getVal robot, room
    read = (str) ->
        m = str.match /Learn Code \(learned hex code: (\w+)\)/
        hex = m[1] if m
    notFound = true
    prompt = ->
        notFound = false
        res.send "ready #{code}"
    setCd = ->
        setVal robot, code, hex
        learnData.stop (->)
        respond res, code, hex
        callback()
    learnData.start host, prompt, setCd, read, false
    if notFound
        res.send "ERROR device not found #{host}"

respond = (res, code, hex) ->
    if hex
        res.send "set #{code} to #{hex}"
    else
        res.send "ERROR #{code} failed to learn code"

get = (robot, res) ->
    key = res.match[1].toLowerCase()
    val = getVal robot, key
    res.send "#{key} = #{val}"

set = (robot, res) ->
    key = res.match[1].toLowerCase()
    val = res.match[2].toLowerCase()
    setVal robot, key, val
    respond res, key, val

delet = (robot, res) ->
    key = res.match[1].toLowerCase()
    deleteVal robot, key
    res.send "deleted #{key}"

list = (robot, res) ->
    keys = getKeys robot
    res.send keys.sort().join '\n'

# Persistence

getVal = (robot, key) ->
    robot.brain.get key

setVal = (robot, key, hex) ->
    robot.brain.set key, hex
    addKey robot, key

deleteVal = (robot, key) ->
    robot.brain.remove key
    deleteKey robot, key

addKey = (robot, key) ->
    keySet = getKeySet robot
    keySet.add key
    setKeySet robot, keySet

deleteKey = (robot, key) ->
    keySet = getKeySet robot
    keySet.delete key
    setKeySet robot, keySet

getKeys = (robot) ->
    str = robot.brain.get '_keys_'
    if str then JSON.parse str else []

getKeySet = (robot) ->
    new Set(getKeys robot)

setKeySet = (robot, keySet) ->
    str = JSON.stringify(Array.from keySet)
    robot.brain.set '_keys_', str
