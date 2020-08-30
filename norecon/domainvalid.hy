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
  [ds &optional proxies [timeout 60]]
  (setv resolver (doto (Resolver :configure False)
                       (setattr "nameservers" proxies)
                       (setattr "lifetime" timeout)))
  (try (-> ds
           (->> (map #%(-> (valid-domain resolver %1)
                           (asyncio.ensure-future))))
           list
           unpack-iterable
           (asyncio.gather :return-exceptions True)
           await
           (->> (filter identity))
           list
           )
       (except [e Exception]
         (print "errors:" e)
         #_(logging.exception "filter valid domain"))))

(defn/a main
  [opts]
  (setv resolver (when opts.resolvers
                   (read-valid-lines opts.resolvers)))
  (setv domains  (if (opts.domains.isatty)
                     (if opts.domain
                         opts.domain
                         (read-valid-lines opts.domains))
                     (+ opts.domain
                        (read-valid-lines opts.domains))))
  (->> (filter-valid-domain domains
                            :proxies resolver
                            :timeout opts.timeout)
       await
       (.join "\n")
       (opts.output.write)))

(defmainf [&rest args]
  (setv opts (parse-args [["-r" "--resolvers"
                           :type (argparse.FileType "r")
                           :help "resolvers file"]
                          ["-d" "--domains"
                           :nargs "?"
                           :type (argparse.FileType "r")
                           :default sys.stdin
                           :help "domains file to check"]
                          ["-t" "--timeout"
                           :type int
                           :default 60
                           :help "domain query timeout (default: %(default)s)"]
                          ["-o" "--output"
                           :nargs "?"
                           :type (argparse.FileType "w")
                           :default sys.stdout
                           :help "output valid domain"]
                          ["domain" :nargs "*" :help "domain to check"]
                          ]
                         (rest args)
                         :description "check domain is resolvable"))
  ;; 不使用async.run 兼容python 3.6
  (doto (asyncio.get-event-loop)
        (.run-until-complete (main opts))
        (.close))
  (logging.info "exit.")
  )
