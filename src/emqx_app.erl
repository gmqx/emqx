

-module(emqx_app).

-define(APP, emqx).


%%--------------------------------------------------------------------
%% Autocluster
%%--------------------------------------------------------------------

start_autocluster() ->
    ekka:callback(prepare, fun emqx:shutdown/1),
    ekka:callback(reboot, fun emqx:reboot/0),
    ekka:autocluster(?APP).

