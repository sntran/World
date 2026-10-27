%% The plugin manager of Wings 3D, with no window: there is no plugin,
%% so a merge of objects has no plugin state to keep.
-module(wings_plugin).
-export([check_plugins/2]).

check_plugins(_Flag, _Pst) -> [].
