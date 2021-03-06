PeerConnection = require 'rtcpeerconnection'
io = require 'socket.io/node_modules/socket.io-client'
gum =require 'getusermedia'
rtc_support = require 'webrtcsupport'


me ={}
me.el = document.getElementById('me')
nogo_el = document.getElementById('nogo')
load_el = document.getElementById('loading')
status_el = document.getElementById('status')
play_el = document.getElementById('playradio')
status_el.style.height ="0px"

if rtc_support.support and rtc_support.supportGetUserMedia
  nogo_el.style.display = "none"
  load_el.style.display = "none"
  me.el.style.display = "block"
  status_el.style.display = "block"
  play_el.addEventListener "click", (evt)->
    warn = "1) This is NOT the direct output from this system. It is the WGXC radio stream.\n"
    warn += "2) You will only hear the output from the 'hearhere' system when we are live (sporadically on Sat. 27.June 4-6pm EST).\n"
    if confirm warn
      radio_el = document.getElementById('radio')
      play_el.style.display = "none"
      play_el.style.visibility= "hidden"
      radio_el.style.display="block"
      radio_el.style.padding="10px"
      radio_el.play() if radio_el
else
  nogo_el.style.display = "block"


return  unless rtc_support.support

#socket =io.connect 'http://10.0.1.71:3000/clients' #, {'force new connection': true}
socket =io.connect 'http://listenhere.info/clients'

configuration =
  iceServers: [url: 'stun:stun.l.google.com:19302']
  #iceServers: [ url: "stun:stun.services.mozilla.com"]



mic_stream=null
mic_stream_src=null
pc=null

socket.on "connect", ()->
  console.log "connected"

socket.on "connect_error", (err)->
  console.log "connect err: #{err?.message}"

socket.on "error", (err)->
  alert "general err: #{err?.message}."

socket.on "disconnect", ()->
  console.log "disconnected.  Please stand by."

socket.on "reconnect", ()->
  console.log "reconnected"

socket.on "reconnecting", (num)->
  console.log "reconnecting, attempt ##{num}"

socket.on "reconnect_error", (err)->
  console.log "reconnect err: #{err.message}"

all_candidates = []
socket.on "ice", (candidate)->
  console.log "socket got ice", candidate
  #candidate = new RTCIceCandidate
  #  sdpMLineIndex: candidate.label
  #  candidate: candidate.candidate
  #pc.processIce candidate
  all_candidates.push candidate

socket.on 'master error', (data)->
  console.log "the central hub is having trouble. Please reload this page if you experience difficulties"

socket.on 'master disconnect', (data)->
  console.log "the central hub has disconnected. Please reload this page."

socket.on 'readyforpeers', ()->
  socket.emit "announce"

socket.on 'pulse', (data)->
  for k,v of other_clients
   delete_client k,v unless data[k]
  for k,v of data
    if k is socket.id
      me.audio = v.audio
    else
      other_clients[k] = {} unless other_clients[k]?
      other_clients[k].el = create_el(k,v) unless other_clients[k]?.el
      other_clients[k].audio = v.audio
  #console.log "got pulse", other_clients
  draw()


# get a local stream, show it in a self-view and add it to be sent
# I read some reports that you must send video
gum {video:false,audio:true}, (err, media_stream)->
  return console.log "gum err #{err.message}" if err
  # for FF, you MUST keep a copy of the original stream that comes from
  # gUM in global scope. see: https://support.mozilla.org/en-US/questions/984179
  mic_stream_src = media_stream
  mic_stream = setup_mic_stream media_stream
  socket.emit "announce"


socket.on 'offer', (offer)->
  console.log "socket got offer", offer
  return unless mic_stream
  pc.close() if pc
  pc = new PeerConnection(configuration)

  #mic_stream.stop() if mic_stream
  #pc.removeStream mic_stream if mic_stream
  all_candidates = []
  #pc.createDataChannel "data"
  pc.addStream mic_stream

  pc.handleOffer offer, (err)->
      return console.log "error on offer #{err.message}" if err
      pc.answerBroadcastOnly (err, answer)->
        return console.log "answerBroadcastOnly err #{err.message}" if err
        console.log "created answer", answer
        socket.emit 'answer', answer

  # send any ice candidates to the other peer
  pc.on "ice", (candidate)->
    console.log "pc got ice", candidate
    socket.emit 'ice', candidate

  pc.on "endOfCandidates", ()->
    for c in all_candidates
      pc.processIce c
    console.log "pc got the end of all candidates"

  pc.on 'answer', ( answer )->
    console.log "pc got answer", answer
    pc.handleAnswer answer

  # remote stream removed
  pc.on 'removeStream', (event)-> console.log "removed stream", event
  #pc.on 'addChannel', ()-> console.log "addChannel"
  #pc.on 'iceConnectionStateChange', ()-> console.log "iceConnectionStateChange", arguments
  #pc.on 'negotiationNeeded', ()-> console.log "negotiationNeeded", arguments
  #pc.on 'signalingStateChange', ()-> console.log "signalingStateChange", argumenTs
  # on peer connection close
  pc.on 'close', ()->
    console.log "rtcpeer closed"


a_ctx = new (
  window.AudioContext ||
  window.webkitAudioContext ||
  window.mozAudioContext ||
  window.oAudioContext ||
  window.msAudioContext
)

log = (msg)->
  console.log msg
  status_el.innerHTML += "#{msg}</br>" if status_el?

log_error = (msg)->
  console.log msg
  status_el.innerHTML += "<div class=\"error\">#{msg}</div>" if status_el?
###
stream_src=null
compressor=null
dest=null
###
setup_mic_stream = (media_stream)->
  if a_ctx?.createMediaStreamSource?
    log "setting up dynamic range compression"
    stream_src = a_ctx.createMediaStreamSource(media_stream)

    compressor = a_ctx.createDynamicsCompressor()
    compressor.threshold.value = -50
    compressor.knee.value = 40
    compressor.ratio.value = 12
    compressor.reduction.value = -20
    compressor.attack.value = 0
    compressor.release.value = 0.25

    dest = a_ctx.createMediaStreamDestination()

    stream_src.connect compressor
    compressor.connect dest
    
    #not sure if this is necessary, but I saw someone else do it
    #media_stream.addTrack(dest.stream.getAudioTracks()[0])
    #media_stream.removeTrack(media_stream.getAudioTracks()[0])

    return dest.stream

  else
    log "no dynamic range compression"
    return media_stream



create_element = (name, attrs)->
  el = document.createElement name
  for k,v of attrs
    el.setAttribute k,v
  return el

delete_client = (k,v)->
  document.body.removeChild v.el
  delete other_clients[k]

set_transform = (el, transform)->
  el.style.webkitTransform = transform
  el.style.MozTransform = transform
  el.style.msTransform = transform
  el.style.OTransform = transform
  el.style.transform = transform

set_class = (el, audio)->
  return el.style.backgroundColor = "red" if audio is "off"
  return el.style.backgroundColor = "green" if audio is "on"
  return el.style.backgroundColor = "orange" if audio is "ready"
  return el.style.backgroundColor = "grey"

center =
  x:0
  y:0

window.onresize = on_window_resize = (e)->
  w = window.innerWidth
  h = window.innerHeight
  center=
    x: w / 2
    y: h / 2
  me.radius = Math.min w/5, h/5
  scale= me.radius/100
  transform = "translate(#{center.x}px, #{center.y}px) scale(#{scale}) "
  set_transform me.el, transform
  draw()

create_el = (k,v)->
  el =document.createElement "div"
  el.id = k
  el.className = "circle"
  set_class el, "trouble"
  document.body.appendChild el
  return el


other_clients ={}

draw = ()->
  len = Object.keys(other_clients).length
  inc = 360 / len
  i=0
  set_class me.el, me.audio
  for k,v of other_clients
    theta = inc*i++
    v.el = create_el(k,v) unless v.el?
    scale= me.radius/100 *0.4
    transform =  "translate(#{center.x}px, #{center.y}px)  rotate(#{theta}deg)  translateX(#{me.radius}px) scale(#{scale})"
    set_transform v.el, transform
    set_class v.el, v.audio

on_window_resize()
