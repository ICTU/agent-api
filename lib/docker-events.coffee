monitor       = require './node-docker-monitor'
request       = require 'request'
_             = require 'lodash'

_.mixin deep: (obj, mapper) ->
  mapper _.mapValues(obj, (v) ->
    if _.isPlainObject(v) then _.deep(v, mapper) else v
  )

replaceDotInKeys = (obj) ->
  _.deep(obj, (x) ->
    _.mapKeys x, (val, key) ->
      if key.indexOf(".") > -1 then key.split('.').join('/') else key
  )

hasDashboardLabels = (event, container) ->
  event?.Actor?.Attributes?['bigboat/status/url'] or container?.Config?.Labels?['bigboat/status/url']

containerHandler = (handler) -> (container) ->
  container = replaceDotInKeys container
  name = container?.Name
  if hasDashboardLabels null, container
    console.log "Processing container '#{name}'"
    handler null, container

eventHandler = (handler) -> (event, container, docker) ->
  container = replaceDotInKeys container
  name = event.Actor?.Attributes?.name or container?.Name or event.id
  if hasDashboardLabels event, container
    console.log "Received event '#{event.status}' for container '#{name}'"
    handler event, container

module.exports.processExistingContainers = (dockerConfig, handler) ->
  monitor.process_existing_containers containerHandler(handler), dockerConfig

module.exports.listen = (dockerConfig, handler) ->
  monitor.listen eventHandler(handler), dockerConfig
