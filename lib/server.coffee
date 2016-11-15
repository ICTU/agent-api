express         = require 'express'
bodyParser      = require 'body-parser'
passport        = require 'passport'
TokenStrategy   = require('passport-token-auth').Strategy
events          = require 'events'
_               = require 'lodash'
topsort         = require 'topsort'

# gets all service names on which the passed service is depending
getDependencies = (doc, service) ->
  _.without _.union(
      doc[service]?.links,
      doc[service]?['volumes-from'],
      doc[service]?['volumes_from'],
      doc[service]?['depends_on'],
      [service]
    )
  , undefined

# returns an array with service dependencies, input for the topsort algorithm
toTopsortArray = (doc) ->
  arr = []
  for service in Object.keys doc
    deps = getDependencies doc, service
    arr = _.union arr, ([service, x] for x in deps)
  arr


createSortedAppdef = (definition) ->
  orderedServices = topsort(toTopsortArray definition).reverse()
  services = {}
  services[service] = definition[service] for service in orderedServices
  services


module.exports = (agentInfo) ->
  httpPort        = process.env.HTTP_PORT or 80
  dockerSocket    = process.env.DOCKER_SOCKET_PATH or '/var/run/docker.sock'
  dockerHost      = process.env.DOCKER_HOST
  authToken       = process.env.AUTH_TOKEN

  unless authToken
    console.error "AUTH_TOKEN is required!"
    process.exit 1

  eventEmitter = new events.EventEmitter()

  passport.use new TokenStrategy {}, (token, cb) ->
    cb null, authToken == token

  app = express()
  app.use passport.initialize()
  app.use bodyParser.json()
  app.use bodyParser.urlencoded extended: false
  authenticate = passport.authenticate('token', { session: false })

  emit = (action) -> (req, res) ->
    eventEmitter.emit action, req.params, req.body, (err, data) ->
      if err
        console.error err
        res.status(500).end('error')
      else
        res.status(200).json(data)

  run = (action) -> (req, res) ->
    data = req.body
    if data.app and data.instance
      data.app._definition = data.app.definition
      data.app.definition = createSortedAppdef data.app._definition
      eventEmitter.emit action, data
      res.status(200).end('thanks')
    else res.status(422).end 'appInfo not provided'

  app.post '/app/install-and-run', authenticate, run('start')

  app.post '/app/start', authenticate, run('start')
  app.post '/app/stop', authenticate, run('stop')

  app.get '/datastore/usage', authenticate, emit '/datastore/usage'

  app.get '/storage/list', authenticate, emit '/storage/list'  
  app.get '/storage/:name/size', authenticate, emit '/storage/size'
  app.delete '/storage/:name', authenticate, emit '/storage/delete'
  app.put '/storage', authenticate, emit '/storage/create'

  sendPong = (req, res) -> res.end('pong')
  app.get '/ping', sendPong
  app.get '/auth-ping', authenticate, sendPong

  app.get '/version', (req, res) ->
    obj =
      api: (require '../package.json').version
      agent: agentInfo

    res.end JSON.stringify obj

  server = app.listen httpPort, ->
    host = server.address().address
    port = server.address().port
    console.log 'Listening on http://%s:%s', host, port

  eventEmitter # return the eventEmitter so clients can register callbacks
