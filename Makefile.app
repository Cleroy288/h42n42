OCSIGENSERVER     := ocsigenserver

DIST_DIRS         := $(ETCDIR) $(DATADIR) $(LIBDIR) $(LOGDIR) \
                     $(ELIOMSTATICDIR) $(shell dirname $(CMDPIPE))

CONF_FILE         := $(TEST_PREFIX)$(ETCDIR)/$(PROJECT_NAME).conf

.PHONY: all build build-dune config-dirs config-files static-copy clean fclean re run

all: build

build: build-dune config-files static-copy

build-dune:
	dune build @$(PROJECT_NAME)

$(addprefix $(TEST_PREFIX), $(DIST_DIRS)):
	mkdir -p $@

config-dirs: $(addprefix $(TEST_PREFIX), $(DIST_DIRS))

config-files: config-dirs
	@JS_SRC=""; \
	if [ -f _build/default/src/client/$(PROJECT_NAME).bc.js ]; then \
		JS_SRC="_build/default/src/client/$(PROJECT_NAME).bc.js"; \
	elif [ -f _build/default/client/$(PROJECT_NAME).bc.js ]; then \
		JS_SRC="_build/default/client/$(PROJECT_NAME).bc.js"; \
	fi; \
	if [ -n "$$JS_SRC" ]; then \
		if command -v md5sum >/dev/null 2>&1; then \
			HASH=`md5sum $$JS_SRC | cut -d ' ' -f 1`; \
		else \
			HASH=`md5 -q $$JS_SRC 2>/dev/null || echo "default"`; \
		fi; \
		cp -f $$JS_SRC $(TEST_PREFIX)$(ELIOMSTATICDIR)/$(PROJECT_NAME)_$${HASH}.js; \
		cp -f $$JS_SRC $(TEST_PREFIX)$(ELIOMSTATICDIR)/$(PROJECT_NAME).js; \
	fi
	@if [ -d _build/default/src ]; then \
		cp -f _build/default/src/$(PROJECT_NAME).cm* $(TEST_PREFIX)$(LIBDIR)/ 2>/dev/null || true; \
	elif [ -d _build/default ]; then \
		cp -f _build/default/$(PROJECT_NAME).cm* $(TEST_PREFIX)$(LIBDIR)/ 2>/dev/null || true; \
	fi
	@sed -e 's|%%PORT%%|$(PORT)|g' \
	     -e 's|%%LOGDIR%%|$(TEST_PREFIX)$(LOGDIR)|g' \
	     -e 's|%%DATADIR%%|$(TEST_PREFIX)$(DATADIR)|g' \
	     -e 's|%%DEBUGMODE%%|<debugmode/>|g' \
	     -e 's|%%CMDPIPE%%|$(TEST_PREFIX)$(CMDPIPE)|g' \
	     -e 's|%%STATICDIR%%|$(LOCAL_STATIC)|g' \
	     -e 's|%%ELIOMSTATICDIR%%|$(TEST_PREFIX)$(ELIOMSTATICDIR)|g' \
	     -e 's|%%LIBDIR%%|$(TEST_PREFIX)$(LIBDIR)|g' \
	     -e 's|%%PROJECT_NAME%%|$(PROJECT_NAME)|g' \
	     $(PROJECT_NAME).conf.in > $(CONF_FILE)

static-copy: config-dirs
	@mkdir -p $(TEST_PREFIX)$(ELIOMSTATICDIR)/css
	@mkdir -p $(TEST_PREFIX)$(ELIOMSTATICDIR)/img
	@mkdir -p $(TEST_PREFIX)$(ELIOMSTATICDIR)/audio
	@cp -rf $(LOCAL_STATIC)/css/* $(TEST_PREFIX)$(ELIOMSTATICDIR)/css/ 2>/dev/null || true
	@cp -rf $(LOCAL_STATIC)/img/* $(TEST_PREFIX)$(ELIOMSTATICDIR)/img/ 2>/dev/null || true
	@cp -rf $(LOCAL_STATIC)/audio/* $(TEST_PREFIX)$(ELIOMSTATICDIR)/audio/ 2>/dev/null || true

run: all
	$(OCSIGENSERVER) -c $(CONF_FILE)

clean:
	dune clean

fclean: clean
	rm -rf $(TEST_PREFIX)

re: fclean all
