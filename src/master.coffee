PeerConnection = require 'rtcpeerconnection'
io = require 'socket.io/node_modules/socket.io-client'
a_ctx = new (
  window.AudioContext ||
  window.webkitAudioContext ||
  window.mozAudioContext ||
  window.oAudioContext ||
  window.msAudioContext
)


socket =io.connect 'http://10.0.1.71:3000/master'
#socket =io.connect 'http://192.168.0.61:3000/master'

configuration =
  iceServers: [url: 'stun:stun.l.google.com:19302']

clients = {}
remove_audio = (peer_id)->
  audio_el = document.getElementById peer_id
  if audio_el
    audio_el.volume=0
    audio_el.srcObject=null if audio_el?.srcObject?
    audio_el.mozSrcObject=null if audio_el?.mozSrcObject?
    audio_el.src = "" if audio_el?.src
    document.body.removeChild audio_el
    delete clients[peer_id]

requestAnimationFrame = requestAnimationFrame || window.mozRequestAnimationFrame || window.webkitRequestAnimationFrame
trigger_adsr = (audio_el, dur)->
  return console.error "missing params to trigger_adsr" unless audio_el and dur
  start = window.mozAnimationStartTime || Date.now()
  set_volume = (t)->
    v = Math.sin( (Math.PI *t)/(dur-1))
    audio_el.volume = Math.max 0, v
  draw = ()->
      now = Date.now()
      diff = now - start
      set_volume diff
      requestAnimationFrame draw if diff < dur
  requestAnimationFrame draw

setup_audio = (peer_id, media_stream)->
  console.log "about to set up audio"
  return console.error "missing params in setup_audio" unless media_stream and  peer_id  and clients?[peer_id]?
  audio_el = document.createElement "audio"
  if audio_el.srcObject?
    console.log "got a normal src"
    audio_el.srcObject = media_stream
  else if audio_el.mozSrcObject?
    console.log "got a moz src"
    audio_el.mozSrcObject = media_stream
  else if URL?.createObjectURL?
    console.log "got a URL src"
    audio_el.src = URL.createObjectURL media_stream
  else
    return console.error "Couldn't add the audio component"
  audio_el.id = peer_id
  audio_el.controls =true
  document.body.appendChild audio_el
  #audio_el.volume=0
  audio_el.play()
  clients[peer_id].audio_el = audio_el
  #clients[peer_id].media_stream = media_stream


socket.on "eskannnureinegeben", ()->
  alert "sorry, there can only be one master"

socket.on "connect", ()->
  console.log "connected"

socket.on "disconnect", ()->
  alert "disconnected"

socket.on "reconnect", ()->
  console.log "reconnected"

socket.on "reconnecting", (num)->
  console.log "reconnecting, attempt ##{num}"

socket.on "reconnect_error", (err)->
  console.log "reconnect err: #{err.message}"


socket.on 'newpeer', (peer_id)->
  pc = new PeerConnection(configuration)
  clients[peer_id] =
    pc:pc

  # send any ice candidates to the other peer
  pc.on "ice", (candidate)->
    console.log "pc got ice from #{peer_id}", pc
    socket.emit "ice", candidate

  pc.on 'answer', (answer)->
    console.log "#pc got answer from #{peer_id}", answer
    pc.handleAnswer answer

  # remote stream added
  pc.on 'addStream', (evt)->
    console.log "got addStream event from #{peer_id}"
    setup_audio peer_id, evt.stream

  pc.on 'removeStream', (evt)->
    console.log "got removeStream event from #{peer_id}", evt
    remove_audio peer_id

  pc.on 'close', ()->
    console.log "got close event from #{peer_id}"
    remove_audio peer_id

  #pc.on 'addChannel', ()-> console.log "addChannel"
  #pc.on 'iceConnectionStateChange', ()-> console.log "iceConnectionStateChange", arguments
  #pc.on 'negotiationNeeded', ()-> console.log "negotiationNeeded", arguments
  #pc.on 'signalingStateChange', ()-> console.log "signalingStateChange", arguments

  pc.offer
    mandatory:
      OfferToReceiveAudio: true
      OfferToReceiveVideo: false
  ,(err, offer)->
    return console.log "create offer err #{err.message}" if err
    offer.peer_id = peer_id
    console.log "created offer", offer
    socket.emit 'offer', offer

socket.on 'disconnect peer', (peer_id)->
  console.log "#{peer_id} has disconnected"
  clients[peer_id].pc.close( ) if peer_id and clients[peer_id]

socket.on 'ice', (candidate)->
  return console.log "got candidate but can't process" unless candidate?.peer_id and clients[candidate.peer_id]?
  peer_id = candidate.peer_id
  delete candidate.peer_id
  console.log "socket got ice", candidate
  clients[peer_id].pc.processIce candidate

socket.on 'answer', (answer)->
  return console.log "got answer but can't pick up" unless answer?.peer_id and clients[answer.peer_id]?
  peer_id = answer.peer_id
  delete answer.peer_id
  console.log "got answer", answer
  clients[peer_id].pc.handleAnswer answer


t=0
setInterval( ()->
  now = Date.now()
  len = Math.max Object.keys(clients).length,2
  idx=t%len
  i=0
  all={}
  for k,a of clients
    if a.audio_el
      if i++ is idx
        all[k] =
          audio: "on"
        #trigger_adsr(a.audio_el, 2000)
      else
        all[k] =
          audio: "off"
  for k,a of clients
    socket.emit "pulse", all
  t++
, 1500)

