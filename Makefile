.PHONY: all compile test cover xref dialyzer type_check lint hank format format_verify \
        run smoke clean

## Everything CI runs, in the same order.
all: compile xref type_check test dialyzer lint hank format_verify cover

compile:
	rebar3 compile

test:
	rebar3 eunit

cover:
	rebar3 cover

xref:
	rebar3 xref

dialyzer:
	rebar3 dialyzer

hank:
	rebar3 hank

format:
	rebar3 fmt

format_verify:
	rebar3 fmt --check

type_check:
	@output=$$(elp eqwalize-all); \
	echo "$$output"; \
	if ! echo "$$output" | grep -q "NO ERRORS"; then \
		exit 1; \
	fi

lint:
	@output=$$(elp lint --rebar --read-config); \
	echo "$$output"; \
	if ! echo "$$output" | grep -q "No diagnostics reported"; then \
		exit 1; \
	fi

## The real thing: a docker cluster, every scenario, every registry.
run:
	./run.sh

## One registry with short timings, to check the harness itself works.
smoke:
	SETTLE_MS=8000 ./run.sh global

clean:
	rebar3 clean
	rm -rf _build results/*.result
