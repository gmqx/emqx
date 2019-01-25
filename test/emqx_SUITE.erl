

-module(emqx_SUITE).



raw_recv_pase(P) ->
  emqx_frame:parse(P, {none, #{max_packet_size => ?MAX_PACKET_SIZE,
                               version         => ?MQTT_PROTO_V4} }).
