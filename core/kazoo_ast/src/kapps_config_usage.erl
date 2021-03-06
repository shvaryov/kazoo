-module(kapps_config_usage).

-export([process_project/0, process_app/1, process_module/1
        ,to_schema_docs/0
        ]).

-include_lib("kazoo_ast/include/kz_ast.hrl").

to_schema_docs() ->
    to_schema_docs(process_project()).

to_schema_docs(Schemas) ->
    kz_json:foreach(fun update_schema/1, Schemas).

update_schema({Name, AutoGenSchema}) ->
    Path = kz_ast_util:schema_path(<<"system_config.", Name/binary, ".json">>),

    SchemaDoc = schema_doc(Name, Path),

    Updated = kz_json:merge_recursive(AutoGenSchema, SchemaDoc),

    'ok' = file:write_file(Path, kz_json:encode(Updated)).

schema_doc(Name, Path) ->
    kz_ast_util:ensure_file_exists(Path),
    {'ok', Bin} = file:read_file(Path),
    ensure_id(Name, kz_json:decode(Bin)).

ensure_id(Name, JObj) ->
    ID = <<"system_config.", Name/binary>>,
    case kz_doc:id(JObj) of
        ID -> JObj;
        _ ->
            kz_json:set_value(<<"description">>
                             ,<<"Schema for ", Name/binary, " system_config">>
                             ,kz_doc:set_id(JObj, ID)
                             )
    end.

process_project() ->
    Core = siblings_of('kazoo'),
    Apps = siblings_of('sysconf'),
    lists:foldl(fun process_app/2, kz_json:new(), Core ++ Apps).

siblings_of(App) ->
    [dir_to_app_name(Dir)
     || Dir <- filelib:wildcard(filename:join([code:lib_dir(App), "..", "*"])),
        filelib:is_dir(Dir)
    ].

dir_to_app_name(Dir) ->
    kz_util:to_atom(filename:basename(Dir), 'true').

-spec process_app(atom()) -> kz_json:object().
process_app(App) ->
    process_app(App, kz_json:new()).

process_app(App, Schemas) ->
    case application:get_key(App, 'modules') of
        {'ok', Modules} ->
            lists:foldl(fun module_to_schema/2, Schemas, Modules);
        'undefined' ->
            'ok' = application:load(App),
            process_app(App, Schemas)
    end.

process_module(Module) ->
    module_to_schema(Module, kz_json:new()).

module_to_schema(Module, Schemas) ->
    case kz_ast_util:module_ast(Module) of
        'undefined' -> 'undefined';
        {M, AST} ->
            Fs = kz_ast_util:add_module_ast([], M, AST),
            functions_to_schema(Fs, Schemas)
    end.

functions_to_schema(Fs, Schemas) ->
    lists:foldl(fun function_to_schema/2
               ,Schemas
               ,Fs
               ).

function_to_schema({_Module, _Function, _Arity, Clauses}, Schemas) ->
    clauses_to_schema(Clauses, Schemas).

clauses_to_schema(Clauses, Schemas) ->
    lists:foldl(fun clause_to_schema/2
               ,Schemas
               ,Clauses
               ).

clause_to_schema(?CLAUSE(_Args, _Guards, Expressions), Schemas) ->
    expressions_to_schema(Expressions, Schemas).

expressions_to_schema(Expressions, Schemas) ->
    lists:foldl(fun expression_to_schema/2
               ,Schemas
               ,Expressions
               ).

expression_to_schema(?MOD_FUN_ARGS('kapps_config', F, Args), Schemas) ->
    config_to_schema(F, Args, Schemas);
expression_to_schema(?MOD_FUN_ARGS('ecallmgr_config', F, Args), Schemas) ->
    config_to_schema(F, [?BINARY_STRING(<<"ecallmgr">>, 0) | Args], Schemas);
expression_to_schema(?MOD_FUN_ARGS(_M, _F, Args), Schemas) ->
    expressions_to_schema(Args, Schemas);
expression_to_schema(?DYN_MOD_FUN(_M, _F), Schemas) ->
    Schemas;
expression_to_schema(?FUN_ARGS(_F, Args), Schemas) ->
    expressions_to_schema(Args, Schemas);
expression_to_schema(?GEN_MFA(_M, _F, _Arity), Schemas) ->
    Schemas;
expression_to_schema(?FA(_F, _Arity), Schemas) ->
    Schemas;
expression_to_schema(?BINARY_OP(_Name, First, Second), Schemas) ->
    expressions_to_schema([First, Second], Schemas);
expression_to_schema(?UNARY_OP(_Name, First), Schemas) ->
    expression_to_schema(First, Schemas);
expression_to_schema(?CATCH(Expression), Schemas) ->
    expression_to_schema(Expression, Schemas);
expression_to_schema(?TRY_BODY(Body, Clauses), Schemas) ->
    clauses_to_schema(Clauses
                     ,expression_to_schema(Body, Schemas)
                     );
expression_to_schema(?TRY_EXPR(Expr, Clauses, CatchClauses), Schemas) ->
    clauses_to_schema(Clauses ++ CatchClauses
                     ,expressions_to_schema(Expr, Schemas)
                     );
expression_to_schema(?TRY_BODY_AFTER(Body, Clauses, CatchClauses, AfterBody), Schemas) ->
    clauses_to_schema(Clauses ++ CatchClauses
                     ,expressions_to_schema(Body ++ AfterBody, Schemas)
                     );
expression_to_schema(?LC(Expr, Qualifiers), Schemas) ->
    expressions_to_schema([Expr | Qualifiers], Schemas);
expression_to_schema(?LC_GENERATOR(Pattern, Expr), Schemas) ->
    expressions_to_schema([Pattern, Expr], Schemas);
expression_to_schema(?BC(Expr, Qualifiers), Schemas) ->
    expressions_to_schema([Expr | Qualifiers], Schemas);
expression_to_schema(?LC_BIN_GENERATOR(Pattern, Expr), Schemas) ->
    expressions_to_schema([Pattern, Expr], Schemas);
expression_to_schema(?ANON(Clauses), Schemas) ->
    clauses_to_schema(Clauses, Schemas);
expression_to_schema(?GEN_FUN_ARGS(?ANON(Clauses), Args), Schemas) ->
    clauses_to_schema(Clauses
                     ,expressions_to_schema(Args, Schemas)
                     );
expression_to_schema(?VAR(_), Schemas) ->
    Schemas;
expression_to_schema(?BINARY_MATCH(_), Schemas) ->
    Schemas;
expression_to_schema(?STRING(_), Schemas) ->
    Schemas;
expression_to_schema(?GEN_RECORD(_NameExpr, _RecName, Fields), Schemas) ->
    expressions_to_schema(Fields, Schemas);
expression_to_schema(?RECORD(_Name, Fields), Schemas) ->
    expressions_to_schema(Fields, Schemas);
expression_to_schema(?RECORD_FIELD_BIND(_Key, Value), Schemas) ->
    expression_to_schema(Value, Schemas);
expression_to_schema(?GEN_RECORD_FIELD_ACCESS(_RecordName, _Name, Value), Schemas) ->
    expression_to_schema(Value, Schemas);
expression_to_schema(?RECORD_INDEX(_Name, _Field), Schemas) ->
    Schemas;
expression_to_schema(?RECORD_FIELD_REST, Schemas) ->
    Schemas;
expression_to_schema(?DYN_FUN_ARGS(_F, Args), Schemas) ->
    expressions_to_schema(Args, Schemas);
expression_to_schema(?DYN_MOD_FUN_ARGS(_M, _F, Args), Schemas) ->
    expressions_to_schema(Args, Schemas);
expression_to_schema(?MOD_DYN_FUN_ARGS(_M, _F, Args), Schemas) ->
    expressions_to_schema(Args, Schemas);
expression_to_schema(?GEN_MOD_FUN_ARGS(MExpr, FExpr, Args), Schemas) ->
    expressions_to_schema([MExpr, FExpr | Args], Schemas);
expression_to_schema(?ATOM(_), Schemas) ->
    Schemas;
expression_to_schema(?INTEGER(_), Schemas) ->
    Schemas;
expression_to_schema(?FLOAT(_), Schemas) ->
    Schemas;
expression_to_schema(?CHAR(_), Schemas) ->
    Schemas;
expression_to_schema(?TUPLE(_Elements), Schemas) ->
    Schemas;
expression_to_schema(?EMPTY_LIST, Schemas) ->
    Schemas;
expression_to_schema(?LIST(Head, Tail), Schemas) ->
    expressions_to_schema([Head, Tail], Schemas);
expression_to_schema(?RECEIVE(Clauses), Schemas) ->
    clauses_to_schema(Clauses, Schemas);
expression_to_schema(?RECEIVE(Clauses, AfterExpr, AfterBody), Schemas) ->
    expressions_to_schema([AfterExpr | AfterBody]
                         ,clauses_to_schema(Clauses, Schemas)
                         );
expression_to_schema(?LAGER, Schemas) ->
    Schemas;
expression_to_schema(?MATCH(LHS, RHS), Schemas) ->
    expressions_to_schema([LHS, RHS], Schemas);
expression_to_schema(?BEGIN_END(Exprs), Schemas) ->
    expressions_to_schema(Exprs, Schemas);
expression_to_schema(?CASE(Expression, Clauses), Schemas) ->
    clauses_to_schema(Clauses
                     ,expression_to_schema(Expression, Schemas)
                     );
expression_to_schema(?IF(Clauses), Schemas) ->
    clauses_to_schema(Clauses, Schemas);
expression_to_schema(?MAP_CREATION(Exprs), Schemas) ->
    expressions_to_schema(Exprs, Schemas);
expression_to_schema(?MAP_UPDATE(_Var, Exprs), Schemas) ->
    expressions_to_schema(Exprs, Schemas);
expression_to_schema(?MAP_FIELD_ASSOC(K, V), Schemas) ->
    expressions_to_schema([K, V], Schemas);
expression_to_schema(?MAP_FIELD_EXACT(K, V), Schemas) ->
    expressions_to_schema([K, V], Schemas).

config_to_schema('get_all_kvs', _Args, Schemas) ->
    Schemas;
config_to_schema('flush', _Args, Schemas) ->
    Schemas;
config_to_schema('migrate', _Args, Schemas) ->
    Schemas;
config_to_schema(F, [Cat, K], Schemas) ->
    config_to_schema(F, [Cat, K, 'undefined'], Schemas);
config_to_schema(F, [Cat, K, Default, _Node], Schemas) ->
    config_to_schema(F, [Cat, K, Default], Schemas);
config_to_schema(F, [Cat, K, Default], Schemas) ->
    Document = category_to_document(Cat),

    Key = key_to_key_path(K),

    config_key_to_schema(F, Document, Key, Default, Schemas).

config_key_to_schema(_F, _Document, 'undefined', _Default, Schemas) ->
    Schemas;
config_key_to_schema(_F, 'undefined', _Key, _Default, Schemas) ->
    Schemas;
config_key_to_schema(F, Document, Key, Default, Schemas) ->
    Properties = guess_properties(Key, guess_type(F, Default), Default),

    Existing = kz_json:get_json_value([Document, <<"properties">> | Key]
                                     ,Schemas
                                     ,kz_json:new()
                                     ),

    Updated = kz_json:merge_jobjs(Existing, Properties),

    kz_json:set_value([Document, <<"properties">> | Key], Updated, Schemas).

category_to_document(?VAR(_)) -> 'undefined';
category_to_document(Cat) ->
    kz_ast_util:binary_match_to_binary(Cat).

key_to_key_path(?ATOM(A)) -> [kz_util:to_binary(A)];
key_to_key_path(?VAR(_)) -> 'undefined';
key_to_key_path(?EMPTY_LIST) -> [];
key_to_key_path(?LIST(?MOD_FUN_ARGS('kapps_config', _F, [Doc, Field | _]), Tail)) ->
    [iolist_to_binary([${
                      ,kz_ast_util:binary_match_to_binary(Doc)
                      ,"."
                      ,kz_ast_util:binary_match_to_binary(Field)
                      ,$}
                      ]
                     )
    ,<<"properties">>
         | key_to_key_path(Tail)
    ];
key_to_key_path(?LIST(?MOD_FUN_ARGS('kz_util', 'to_binary', [?VAR(Name)]), Tail)) ->
    [iolist_to_binary([${, kz_util:to_binary(Name), $}])
    ,<<"properties">>
         | key_to_key_path(Tail)
    ];

key_to_key_path(?MOD_FUN_ARGS('kz_util', 'to_binary', [?VAR(Name)])) ->
    [iolist_to_binary([${, kz_util:to_binary(Name), $}])];

key_to_key_path(?GEN_FUN_ARGS(_F, _Args)) ->
    'undefined';

key_to_key_path(?LIST(?VAR(Name), Tail)) ->
    [iolist_to_binary([${, kz_util:to_binary(Name), $}])
    ,<<"properties">>
         | key_to_key_path(Tail)
    ];
key_to_key_path(?LIST(Head, Tail)) ->
    [kz_ast_util:binary_match_to_binary(Head)
    ,<<"properties">>
         | key_to_key_path(Tail)
    ];
key_to_key_path(?BINARY_MATCH(K)) ->
    [kz_ast_util:binary_match_to_binary(K)].

guess_type('is_true', _Default) -><<"boolean">>;
guess_type('get_is_true', _Default) -><<"boolean">>;
guess_type('get_boolean', _Default) -><<"boolean">>;
guess_type('get', Default) -> guess_type_by_default(Default);
guess_type('fetch', Default) -> guess_type_by_default(Default);
guess_type('get_non_empty', Default) -> guess_type_by_default(Default);
guess_type('get_node_value', Default) -> guess_type_by_default(Default);
guess_type('get_binary', _Default) -> <<"string">>;
guess_type('get_ne_binary', _Default) -> <<"string">>;
guess_type('get_json', _Default) -> <<"object">>;
guess_type('get_string', _Default) -> <<"string">>;
guess_type('get_integer', _Default) -> <<"integer">>;
guess_type('get_float', _Default) -> <<"number">>;
guess_type('get_atom', _Default) -> <<"string">>;
guess_type('set_default', _Default) -> 'undefined';
guess_type('set', Default) -> guess_type_by_default(Default);
guess_type('set_node', Default) -> guess_type_by_default(Default);
guess_type('update_default', Default) -> guess_type_by_default(Default).

guess_type_by_default('undefined') -> 'undefined';
guess_type_by_default(?ATOM('undefined')) -> 'undefined';
guess_type_by_default(?ATOM('true')) -> <<"boolean">>;
guess_type_by_default(?ATOM('false')) -> <<"boolean">>;
guess_type_by_default(?ATOM(_)) -> <<"string">>;
guess_type_by_default(?VAR(_V)) -> 'undefined';
guess_type_by_default(?EMPTY_LIST) -> <<"array">>;
guess_type_by_default(?LIST(_Head, _Tail)) -> <<"array">>;
guess_type_by_default(?BINARY_MATCH(_V)) -> <<"string">>;
guess_type_by_default(?INTEGER(_I)) -> <<"integer">>;
guess_type_by_default(?FLOAT(_F)) -> <<"number">>;
guess_type_by_default(?BINARY_OP(_Op, Arg1, _Arg2)) ->
    guess_type_by_default(Arg1);
guess_type_by_default(?MOD_FUN_ARGS('kapps_config', F, [_Cat, _Key])) ->
    guess_type(F, 'undefined');
guess_type_by_default(?MOD_FUN_ARGS('kapps_config', F, [_Cat, _Key, Default |_])) ->
    guess_type(F, Default);
guess_type_by_default(?MOD_FUN_ARGS('kz_json', 'new', [])) -> <<"object">>;
guess_type_by_default(?MOD_FUN_ARGS('kz_json', 'from_list', _Args)) -> <<"object">>;
guess_type_by_default(?MOD_FUN_ARGS('kz_json', 'set_value', [_K, V, _J])) ->
    guess_type_by_default(V);
guess_type_by_default(?MOD_FUN_ARGS('kz_util', 'anonymous_caller_id_number', [])) -> <<"string">>;
guess_type_by_default(?MOD_FUN_ARGS('kz_util', 'anonymous_caller_id_name', [])) -> <<"string">>;
guess_type_by_default(?MOD_FUN_ARGS('kz_util', 'to_integer', _Args)) -> <<"integer">>.

guess_properties(<<_/binary>> = Key, Type, Default) ->
    kz_json:from_list(
      props:filter_undefined(
        [{<<"type">>, Type}
        ,{<<"description">>, <<>>}
        ,{<<"name">>, Key}
        ,{<<"default">>, try default_value(Default) catch _:_ -> 'default' end}
        ]
       )
     );
guess_properties([<<_/binary>> = Key], Type, Default) ->
    guess_properties(Key, Type, Default);
guess_properties([Key, <<"properties">>], Type, Default) ->
    guess_properties(Key, Type, Default);
guess_properties([_Key, <<"properties">> | Rest], Type, Default) ->
    guess_properties(Rest, Type, Default).

default_value('undefined') -> 'undefined';
default_value(?ATOM('true')) -> 'true';
default_value(?ATOM('false')) -> 'false';
default_value(?ATOM('undefined')) -> 'undefined';
default_value(?ATOM(V)) -> kz_util:to_binary(V);
default_value(?VAR(_)) -> 'undefined';
default_value(?STRING(S)) -> kz_util:to_binary(S);
default_value(?INTEGER(I)) -> I;
default_value(?FLOAT(F)) -> F;
default_value(?BINARY_OP(Op, Arg1, Arg2)) ->
    erlang:Op(default_value(Arg1), default_value(Arg2));
default_value(?BINARY_MATCH(Match)) -> kz_ast_util:binary_match_to_binary(Match);
default_value(?EMPTY_LIST) -> [];
default_value(?TUPLE([Key, Value])) ->
    {default_value(Key), default_value(Value)};
default_value(?LIST(Head, Tail)) ->
    [default_value(Head) | default_value(Tail)];
default_value(?MOD_FUN_ARGS('kz_json', 'from_list', L)) ->
    default_values_from_list(L);
default_value(?MOD_FUN_ARGS('kz_json', 'new', [])) ->
    kz_json:new();
default_value(?MOD_FUN_ARGS(_M, _F, _Args)) -> 'undefined';
default_value(?FUN_ARGS(_F, _Args)) ->
    'undefined'.

default_values_from_list(KVs) ->
    lists:foldl(fun default_value_from_kv/2
               ,kz_json:new()
               ,KVs
               ).

default_value_from_kv(KV, Acc) ->
    KVs = props:filter_undefined(default_value(KV)),
    kz_json:set_values(KVs, Acc).
