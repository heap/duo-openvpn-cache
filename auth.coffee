#!/usr/bin/env coffee

Promise = require 'bluebird'
crypto = require 'crypto'
Duo = require 'duo-api'
fs = Promise.promisifyAll require('fs')
log = new (require 'log')(process.env.log_level or 'info')
moment = require 'moment'
path = require 'path'

# Custom environment variables set via OpenVPN setenv
duo_host = process.env.duo_host
duo_ikey = process.env.duo_ikey
duo_skey = process.env.duo_skey
cache_dir = process.env.duo_cachedir
cache_hours = process.env.duo_cachehours or 12

# These environment variables are described here: https://openvpn.net/index.php/open-source/documentation/manuals/65-openvpn-20x-manpage.html
certName = process.env.common_name
password = process.env.password
remoteIP = process.env.untrusted_ip
username = process.env.username

getHashForCurrentConnectionAttempt = ->
  connectionDescriptor = JSON.stringify
    certName: certName,
    password: password,
    remoteIP: remoteIP,
    username: username

  hasher = crypto.createHash 'SHA512'
  hasher.update connectionDescriptor
  hasher.digest 'hex'

cleanCachedCredentials = ->
  fs.readdirAsync cache_dir
    .map (filename) ->
      fs.statAsync path.join(cache_dir, filename)
        .then (stat) ->
          {
            stat,
            filename
          }
    .then (files) ->
      deleteIfCreatedBefore = moment().subtract(cache_hours, 'hours').toDate()
      toDelete = files.filter ({stat}) ->
        stat.birthtime < deleteIfCreatedBefore

      Promise.map toDelete, ({filename}) ->
        fs.unlinkAsync path.join(cache_dir, filename)

canUseCachedCredentials = (currentHash) ->
  log.info 'Checking if credentials are cached'
  fs.statAsync path.join(cache_dir, currentHash)
    .then (stat) ->
      {
        connectionHash: currentHash,
        wasAuthed: true
      }
    .catch (err) ->
      {
        connectionHash: currentHash
      }

checkSecondFactor = (authDetails) ->
  duoClient = new Duo
    host: duo_host
    ikey: duo_ikey
    skey: duo_skey

  options =
    username: certName,
    ipaddr: remoteIP

  if password.match /^\d{6}$/
    log.info 'Submitting 2FA code to Duo'
    options.passcode = password
    options.factor = 'passcode'
  else
    log.info 'Requesting push notification from Duo'
    options.factor = 'push'
    options.device = 'auto'

  duoClient.request 'POST', '/auth/v2/auth', options
    .then (response) ->
      authDetails.wasAuthed = response?.stat is 'OK' and response?.response.result is 'allow'
      authDetails.cache = true
      authDetails

cacheCredentials = ({wasAuthed, cache, connectionHash}) ->
  if wasAuthed and cache
    log.info 'Caching credentials'
    fs.openAsync(path.join(cache_dir, connectionHash), 'w')
    .then (->
      {wasAuthed}),
      (err) ->
        log.error 'Failed to cache auth details', err
        {wasAuthed}
  else
    {wasAuthed}

cleanCachedCredentials()
  .then getHashForCurrentConnectionAttempt
  .then canUseCachedCredentials
  .then (authDetails) ->
    return authDetails if authDetails.wasAuthed

    checkSecondFactor authDetails
      .then cacheCredentials
  .then (authDetails) ->
    log.info 'Finished authing', authDetails
    process.exit if authDetails?.wasAuthed then 0 else 1
  .catch (err) ->
    log.error 'Failed to check user authentication', err
    process.exit 1
