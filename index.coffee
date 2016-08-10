server = require './lib/server'
docker = require './lib/docker-events'

module.exports =
  agent: server
  docker: docker
