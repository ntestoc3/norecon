#!/usr/bin/env hy

(require [hy.extra.anaphoric [*]]
         [helpers [*]]
         )

(import os
        logging
        sys
        argparse
        time
        asyncio

        [domainvalid [filter-valid-domain]]
        [retry [retry]]
        [helpers [*]]
        [publicsuffix2 [get-public-suffix PublicSuffixList]]
        )

(defn/a get-domains
  [domain-top-name &optional [tlds ["com" "cn" "org" "jp"]] &kwargs kwargs]
  (logging.info "get wildcard domain for:%s." domain-top-name)
  (-> (map #%(.format "{}.{}" domain-top-name %1) tlds)
      (filter-valid-domain #** kwargs)
      await))

(defn/a get-wildcards-domains
  [wd-domains &kwargs kwargs]
  (-> wd-domains
      (->> (map #%(-> (.split %1 ".")
                      (of -2)
                      (get-domains #** kwargs)
                      (asyncio.ensure-future))))
      list
      unpack-iterable
      (asyncio.gather)
      await
      ;; (doto (->> (logging.info "wildcards domains result:%s")))
      unpack-iterable
      concat))

(defn/a async-main
  [opts]
  (setv resolver (when opts.resolvers
                   (read-valid-lines opts.resolvers)))
  (setv domains  (if (opts.domains.isatty)
                     (if opts.domain
                         opts.domain
                         (read-valid-lines opts.domains))
                     (concat opts.domain
                             (read-valid-lines opts.domains))))
  (setv by-wild #%(.endswith %1 ".*"))
  (setv tlds (-> (PublicSuffixList :psl-file opts.tld-file)
                 (. tlds)))
  (-> domains
      (sorted :key by-wild)
      (group-by :key by-wild)
      (->> (map #%(identity
                    [(if (first %1)
                         "wildcards"
                         "normal")
                     (-> (second %1)
                         list)])))
      dict
      (as-> d
            (concat (some-> (.get d "normal" [])
                            (->> (map get-public-suffix))
                            list
                            )
                    (some-> (.get d "wildcards" [])
                            (get-wildcards-domains
                              :tlds tlds
                              :proxies resolver
                              :timeout opts.timeout)
                            await)))
      ;; (doto (->> (logging.info "result:%s")))
      set
      (->> (.join "\n"))
      (opts.output.write)))


(comment

  (setv ds (-> (open "./wildd.txt")
               read-valid-lines))

  (setv d2 (->> ds
                (map get-public-suffix)
                list))

  )
(defmainf [&rest args]
  (setv opts (parse-args [["-r" "--resolvers"
                           :type (argparse.FileType "r")
                           :help "包含dns解析服务器列表的文件"]
                          ["-t" "--timeout"
                           :type int
                           :default 20
                           :help "域名查询超时时间(秒) (default: %(default)s)"]
                          ["-d" "--domains"
                           :nargs "?"
                           :type (argparse.FileType "r")
                           :default sys.stdin
                           :help "输入的域名，可包含*通配"]
                          ["-tf" "--tld-file"
                           :nargs "?"
                           :type str
                           :help "包含tld列表的文件"]
                          ["-o" "--output"
                           :nargs "?"
                           :type (argparse.FileType "w")
                           :default sys.stdout
                           :help "输出合法的一级域名"]
                          ["-v" "--verbose"
                           :nargs "?"
                           :type int
                           :default 0
                           :help "日志输出级别(0,1,2)　 (default: %(default)s)"]
                          ["domain" :nargs "*" :help "要检测的域名"]
                          ]
                         (rest args)
                         :description "过滤，查找合法的一级域名，可以使用*通配域名后缀(tld)"))
  (set-logging-level opts.verbose)

  (doto (asyncio.get-event-loop)
        (.run-until-complete (async-main opts))
        (.close))
  (logging.info "over!")
  )
