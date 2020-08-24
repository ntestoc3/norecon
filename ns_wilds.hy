#!/usr/bin/env hy

(import sys)
(sys.path.append ".")
(require [hy.extra.anaphoric [*]]
         [helpers [*]]
         )

(import os
        logging
        sys
        argparse
        time
        asyncio

        [ns-valid [filter-valid-domain]]
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
      concat))

(defn/a main
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
(defmain [&rest args]
  (logging.basicConfig :level logging.INFO
                       :handlers [(logging.FileHandler :filename "ns_wilds_app.log")
                                  (logging.StreamHandler sys.stderr)]
                       :style "{"
                       :format "{asctime} [{levelname}] {filename}({funcName})[{lineno}] {message}")

  (setv opts (parse-args [["-r" "--resolvers"
                           :type (argparse.FileType "r")
                           :help "包含dns解析服务器列表的文件"]
                          ["-t" "--timeout"
                           :type int
                           :default 20
                           :help "domain query timeout (default: %(default)s)"]
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
                          ["domain" :nargs "*" :help "要检测的域名"]
                          ]
                         (rest args)
                         :description "过滤，查找合法的一级域名，可以使用*通配域名后缀(tld)"))

  (doto (asyncio.get-event-loop)
        (.run-until-complete (main opts))
        (.close))
  (logging.info "over!")
  )
