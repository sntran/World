%% The progress bar of Wings 3D, with no window: each call does nothing.
%% World builds meshes with the core of Wings 3D and has no window.
-module(wings_pb).
-export([start/1, update/1, update/2, done/0, done/1]).

start(_) -> ok.
update(_) -> ok.
update(_, _) -> ok.
done() -> fun() -> ok end.
done(Result) -> Result.
