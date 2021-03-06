%%%-------------------------------------------------------------------
%%% @copyright (c) 2010-2016, 2600Hz
%%% @doc
%%%
%%% @end
%%% @contributors
%%% Pierre Fenoll
%%%-------------------------------------------------------------------
-module(ci_parsers_util).

%% ci_parsers_util: utilities for parsers.

-export([timestamp/1, timestamp/0]).
-export([open_file/1]).
-export([parse_interval/0]).
-export([make_name/1]).
-export([call_id/1
        ,c_seq/1
        ]).

-include_lib("kazoo/include/kz_types.hrl").
-include_lib("kazoo/include/kz_log.hrl").

%% API

-spec timestamp() -> api_number().
timestamp() ->
    timestamp(os:timestamp()).

-spec timestamp(ne_binary() | kz_now()) -> api_number().
timestamp(<<YYYY:4/binary, "-", MM:2/binary, "-", DD:2/binary, "T"
            ,HH:2/binary, ":", MMM:2/binary, ":", SS:2/binary, "."
            ,Micro:6/binary, "+", _H:2/binary, ":", _M:2/binary, " ", _/binary
          >>) ->
    1.0e-6 * kz_util:to_integer(Micro) +
        calendar:datetime_to_gregorian_seconds(
          {{kz_util:to_integer(YYYY), kz_util:to_integer(MM), kz_util:to_integer(DD)}
          ,{kz_util:to_integer(HH), kz_util:to_integer(MMM), kz_util:to_integer(SS)}
          }
         );
timestamp({_,_,_} = TS) ->
    kz_util:now_s(TS);
timestamp(_) -> 'undefined'.

-spec open_file(iodata()) -> file:io_device().
open_file(Filename) ->
    Options = ['read','append'      %% Read whole file then from its end
              ,'binary'            %% Return binaries instead of lists
              ,'raw','read_ahead'  %% Faster access to file
              ],
    case file:open(Filename, Options) of
        {'ok', IoDevice} -> IoDevice;
        {'error', _FileOpenError} ->
            lager:debug("parser cannot open '~p': ~p", [Filename,_FileOpenError])
    end.

-spec parse_interval() -> pos_integer().
parse_interval() ->
    2 * ?MILLISECONDS_IN_SECOND.  %% Milliseconds

-spec make_name(ne_binary() | {'parser_args', ne_binary(), any()}) -> atom().
make_name(Bin)
  when is_binary(Bin) ->
    binary_to_atom(Bin, 'utf8');
make_name({'parser_args', ListenIP, Port})
  when is_integer(Port) ->
    make_name(<< (kz_util:to_binary(ListenIP))/binary,
                 ":",
                 (kz_util:to_binary(Port))/binary
              >>);
make_name({'parser_args', Filename, _IP, _Port}) ->
    FName = filename:absname(Filename),
    make_name(kz_util:to_binary(FName)).

-spec call_id(ne_binaries()) -> ne_binary().
call_id(Data) ->
    sip_field([<<"Call-ID">>, <<"i">>], Data).

%% @doc Gets the CSeq field from SIP transaction data.
%%   To use with HEP or FreeSwitch data; Kamailio has another format!
-spec c_seq(ne_binaries()) -> ne_binary().
c_seq(Data) ->
    sip_field([<<"CSeq">>], Data).

%% Internals

-spec sip_field(ne_binaries(), ne_binaries()) -> api_binary().
sip_field(_Fields, []) ->
    'undefined';
sip_field(Fields, [Data|Rest]) ->
    case [Val || Field <- Fields,
                 (Val = try_all(Data, Field)) =/= 'false'
         ]
    of
        [] ->
            sip_field(Fields, Rest);
        [Value] ->
            Value
    end.

-spec try_all(ne_binary(), ne_binary()) -> 'false' | ne_binary().
try_all(Data, Field) ->
    FieldSz = byte_size(Field),
    case Data of
        <<Field:FieldSz/binary, _/binary>> ->
            case binary:split(Data, <<": ">>) of
                [_Key, Value0] ->
                    kz_util:truncate_right_binary(Value0, byte_size(Value0));
                _ ->
                    'false'
            end;
        _ ->
            'false'
    end.

%% End of Module.
