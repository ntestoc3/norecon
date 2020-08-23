#!/usr/bin/env hy

(require [hy.extra.anaphoric [*]]
         [helpers [*]]
         )

(import os
        logging
        sys
        argparse
        time

        [retry [retry]]
        [helpers [*]]
        [async-dns [types]]
        [async-dns.resolver [ProxyResolver]]
        asyncio
        )

(defn/a valid-domain?
  [resolver domain]
  (try (setv r (some-> (resolver.query-safe domain types.NS)
                       await
                       (. an)
                       empty?
                       not
                       (when domain)))
       (logging.info "valid domain %s return %s" domain r)
       r
       (except [e Exception]
         (logging.exception "valid domain?"))
       (finally
         (logging.info f"valid domain {domain} return."))))

(defn/a filter-valid-domain
  [ds &optional proxies]
  (logging.info "filter valid domain %s" ds)
  (setv resolver (ProxyResolver :proxies proxies))
  (setv r None)
  (try (setv r (->> ds
                    (map #%(-> (valid-domain? resolver %1)
                               asyncio.create-task))
                    list
                    unpack-iterable
                    asyncio.gather
                    await
                    ;; (filter identity)
                    ;; list
                    ))
       (logging.exception "filter valid domain return:%s" r)
       r
       (except [e Exception]
         (logging.exception "filter valid domain"))
       (finally
         (logging.exception "filter valid domain finally.result:%s" r))))

(defn read-valid-lines
  [f]
  (->> (.read f)
       (.splitlines)
       (filter (comp not empty?))
       list))

(defn/a main
  [opts]
  (setv resolver (when opts.resolvers
                   (read-valid-lines opts.resolvers)))
  (setv domains  (if (opts.domains.isatty)
                     opts.domain
                     (+ opts.domain
                        (read-valid-lines opts.domains))))
  (->> (filter-valid-domain domains :proxies resolver)
       await
       (.join "\n")
       (opts.output.write)))

(defmain [&rest args]
  (logging.basicConfig :level logging.INFO
                       :style "{"
                       :format "{asctime} [{levelname}] {filename}({funcName})[{lineno}] {message}")

  (setv opts (parse-args [["-r" "--resolvers"
                           :type (argparse.FileType "r")
                           :help "resolvers file"]
                          ["-d" "--domains"
                           :nargs "?"
                           :type (argparse.FileType "r")
                           :default sys.stdin
                           :help "domains file to check"]
                          ["-o" "--output"
                           :nargs "?"
                           :type (argparse.FileType "w")
                           :default sys.stdout
                           :help "output valid domain"]
                          ["domain" :nargs "*" :help "domain to check"]
                          ]
                         (rest args)
                         :description "check domain is resolvable"))
  (asyncio.run (main opts))
  (logging.info "exit.")
  )
