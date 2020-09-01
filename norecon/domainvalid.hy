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
           #_(logging.error "valid domain error: %s" e)))))

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

(defn/a async-main
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
                           :help "包含域名解析服务器的文件"]
                          ["-d" "--domains"
                           :nargs "?"
                           :type (argparse.FileType "r")
                           :default sys.stdin
                           :help "包含要检测的域名的文件"]
                          ["-t" "--timeout"
                           :type int
                           :default 60
                           :help "域名查询超时时间(秒) (default: %(default)s)"]
                          ["-o" "--output"
                           :nargs "?"
                           :type (argparse.FileType "w")
                           :default sys.stdout
                           :help "输出文件，保存有效的域名"]
                          ["-v" "--verbose"
                           :nargs "?"
                           :type int
                           :default 0
                           :help "日志输出级别(0,1,2)　 (default: %(default)s)"]
                          ["domain" :nargs "*" :help "要查询的域名"]
                          ]
                         (rest args)
                         :description "检查域名是否可以解析，仅针对一级域名，即有ns记录的域名"))
  (set-logging-level opts.verbose)

  ;; 不使用async.run 兼容python 3.6
  (doto (asyncio.get-event-loop)
        (.run-until-complete (async-main opts))
        (.close))
  (logging.info "exit.")
  )
