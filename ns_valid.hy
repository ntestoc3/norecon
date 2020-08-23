#!/usr/bin/env hy

(require [hy.extra.anaphoric [*]]
         [helpers [*]]
         )

(import os
        logging
        sys
        argparse
        time
        dns

        [retry [retry]]
        [helpers [*]]
        [dns.asyncresolver [Resolver]]
        [dns.rdatatype :as rtype]
        asyncio
        )

(with-decorator (retry Exception :delay 5 :backoff 4 :max-delay 120)
  (defn/a valid-domain
    [resolver domain]
    (try (some-> (resolver.resolve domain :rdtype rtype.NS)
                 await
                 (when domain))
         (except [e [dns.exception.Timeout
                     dns.resolver.NoNameservers
                     dns.resolver.NXDOMAIN
                     dns.resolver.NoAnswer
                     ]]
           None
           #_(logging.error "error valid domain? %s" e)))))

(defn/a filter-valid-domain
  [ds &optional proxies]
  (logging.info "filter valid domain %s" ds)
  (setv resolver (doto (Resolver :configure False)
                       (setattr "nameservers" proxies)
                       (setattr "lifetime" 3)))
  (try (-> ds
           (->> (map #%(-> (valid-domain resolver %1)
                           (asyncio.create-task))))
           list
           unpack-iterable
           (asyncio.gather :return-exceptions True)
           await
           (doto (print " --- return"))
           (->> (filter identity))
           list
           )
       (except [e Exception]
         (print "errors:" e)
         #_(logging.exception "filter valid domain"))))

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
  (logging.basicConfig :level logging.WARN
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
