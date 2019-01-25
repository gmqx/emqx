.PHONY: plugins tests

PROJECT = gmqx
PROJECT_DESCRIPTION = EMQ X Broker

DEPS = jsx gproc gen_rpc ekka esockd cowboy

dep_jsx			= hex-gmqx 2.9.0
dep_gproc		= hex-gmqx 0.8.0
dep_gen_rpc	= git-gmqx https://github.com/gmqx/gen_rpc 2.3.0
dep_esockd	= git-gmqx https://github.com/gmqx/esockd v5.4.3
dep_ekka		= git-gmqx https://github.com/gmqx/ekka v0.5.1
dep_cowboy	= hex-gmqx 2.4.0

NO_AUTOPATCH = cuttlefish

ERLC_OPTS += +debug_info -DAPPLICATION=gmqx

BUILD_DEPS = cuttlefish
dep_cuttlefish = git-gmqx https://github.com/gmqx/cuttlefish v2.2.0

#TEST_DEPS = gmqx_ct_helpers
#dep_gmqx_ct_helplers = git git@github.com:gmqx/gmqx-ct-helpers

TEST_ERLC_OPTS += +debug_info -DAPPLICATION=gmqx

EUNIT_OPTS = verbose

# CT_SUITES = gmqx_frame
## gmqx_trie gmqx_router gmqx_frame gmqx_mqtt_compat

CT_SUITES = gmqx \
			gmqx_access \
			gmqx_keepalive \
			gmqx_mqtt_props \
			gmqx_tables \
			gmqx_listeners \
			gmqx_hooks

CT_NODE_NAME = gmqxct@127.0.0.1
CT_OPTS = -cover test/ct.cover.spec -erl_args -name $(CT_NODE_NAME)

COVER = true

PLT_APPS = sasl asn1 ssl syntax_tools runtime_tools crypto xmerl os_mon inets public_key ssl compiler mnesia
DIALYZER_DIRS := ebin/
DIALYZER_OPTS := --verbbose --statistics -Werror_handling -Wrace_conditions #-Wunmatched_returns

$(shell [ -f erlang.mk ] || curl -s -o erlang.mk https://raw.githubusercontent.com/gmqx/erlmk/master/erlang.mk)
include erlang.mk

clean:: gen-clean

.PHONY: gen-clean
gen-clean:
	@rm -rf bbmustache
	@rm -f etc/gen.gmqx.conf

bbmustache:
	$(verbose) git clone https://github.com/soranoba/bbmustache.git && cd bbmustache && ./rebar3 compile && cd ..

# This hack is to generate a conf file for testing
# relx overlay is used for release
etc/gen.gmqx.conf: bbmustache etc/gmqx.conf
	$(verbose) erl -noshell -pa bbmustache/_build/default/lib/bbmustache/ebin -eval \
		"{ok, Temp} = file:read_file('etc/gmqx.conf'), \
		{ok, Vars0} = file:consult('vars'), \
		Vars = [{atom_to_list(N), list_to_binary(V)} || {N, V} <- Vars0], \
		Targ = bbmustache:render(Temp, Vars), \
		ok = file:write_file('etc/gen.gmqx.conf', Targ), \
		halt(0)."

CUTTLEFISH_SCRIPT = _build/default/lib/cuttlefish/cuttlefish

app.config: $(CUTTLEFISH_SCRIPT) etc/gen.gmqx.conf
	$(verbose) $(CUTTLEFISH_SCRIPT) -l info -e etc/ -c etc/gen.gmqx.conf -i priv/gmqx.schema -d data/

ct: app.config

rebar-cover:
	@rebar3 cover

coveralls:
	@rebar3 coveralls send


$(CUTTLEFISH_SCRIPT): rebar-deps
	@if [ ! -f cuttlefish ]; then make -C _build/default/lib/cuttlefish; fi

rebar-xref:
	@rebar3 xref

rebar-deps:
	@rebar3 get-deps

rebar-eunit: $(CUTTLEFISH_SCRIPT)
	@rebar3 eunit

rebar-compile:
	@rebar3 compile

rebar-ct: app.config
	@rebar3 as test compile
	@ln -s -f '../../../../etc' _build/test/lib/gmqx/
	@ln -s -f '../../../../data' _build/test/lib/gmqx/
	@rebar3 ct -v --readable=false --name $(CT_NODE_NAME) --suite=$(shell echo $(foreach var,$(CT_SUITES),test/$(var)_SUITE) | tr ' ' ',')

rebar-clean:
	@rebar3 clean

distclean::
	@rm -rf _build cover deps logs log data
	@rm -f rebar.lock compile_commands.json cuttlefish

# Below are for version consistency check during erlang.mk and rebar3 dual mode support
none=
space = $(none) $(none)
comma = ,
quote = \"
curly_l = "{"
curly_r = "}"
dep-versions = [$(foreach dep,$(DEPS) $(BUILD_DEPS),$(curly_l)$(dep),$(quote)$(word $(words $(dep_$(dep))),$(dep_$(dep)))$(quote)$(curly_r)$(comma))[]]

.PHONY: dep-vsn-check
dep-vsn-check:
	$(verbose) erl -noshell -eval \
		"MkVsns = lists:sort(lists:flatten($(dep-versions))), \
		{ok, Conf} = file:consult('rebar.config'), \
		{_, Deps1} = lists:keyfind(deps, 1, Conf), \
		{_, Deps2} = lists:keyfind(github_gmqx_deps, 1, Conf), \
		F = fun({N, V}) when is_list(V) -> {N, V}; ({N, {git, _, {branch, V}}}) -> {N, V} end, \
		RebarVsns = lists:sort(lists:map(F, Deps1 ++ Deps2)), \
		case {RebarVsns -- MkVsns, MkVsns -- RebarVsns} of \
			{[], []} -> halt(0); \
			{Rebar, Mk} -> erlang:error({deps_version_descrepancy, [{rebbar, Rebar}, {mk, Mk}]}) \
		end."
