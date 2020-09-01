#!/usr/bin/env hy

(require [hy.extra.anaphoric [*]]
         [helpers [*]]
         )

(import os
        logging
        sys
        argparse
        time
        json
        pprint
        dns

        [retry [retry]]
        [helpers [*]]
        [dns.resolver [Resolver]]
        [dns.rdatatype :as rtype]
        )

(with-decorator (retry Exception :delay 5 :backoff 4 :max-delay 120)
  (defn query-rs
    [resolver domain &optional [rdtype "a"]]
    (try (resolver.resolve domain :rdtype rdtype)
         (except [e [dns.exception.Timeout
                     dns.resolver.NoNameservers
                     dns.resolver.NXDOMAIN
                     dns.resolver.NoAnswer
                     ]]
           None
           #_(logging.error "error valid domain? %s" e)))))

(defn parse-answer
  [r]
  {"name" (-> (str r.qname)
              (.rstrip "."))
   "type" (rtype.to-text r.rdtype)
   "expiration" r.expiration
   "canonical-name" (-> (str r.canonical-name)
                        (.rstrip "."))
   "result" (lfor a r.rrset
                  (str a))})

(defn get-domain-records
  [resolver domain &optional [types ["a" "aaaa" "mx" "ns" "txt" "cname" "soa"]]]
  (->> types
       (pmap #%(query-rs resolver domain :rdtype %1))
       (filter identity)
       (map parse-answer)
       list))

(defn get-records
  [domain &optional resolver [timeout 30] types]
  "获取域名`domain`的查询记录"
  (logging.info "get records for %s." domain)
  (setv rsv (if resolver
                (doto (Resolver :configure False)
                      (setattr "nameservers" resolver))
                (Resolver)))
  (setv rsv.lifetime timeout)
  (get-domain-records rsv domain
                      #** (if types
                              {"types" types}
                              {})))

(comment
  (setv rsv (Resolver))

  (pprint.pprint (get-domain-records rsv "bing.com"))
  )

(defn valid-rdtype?
  [rdt]
  (try (rtype.from-text rdt)
       True
       (except [e dns.rdatatype.UnknownRdatatype]
         False)))

(defn rdtypes
  [rs]
  (->2> (rs.split ",")
        (map str.strip)
        (lfor r
         (if (valid-rdtype? r)
             r
             (raise (argparse.ArgumentTypeError f"{r} not valid Rdatatype"))))))

(defmainf [&rest args]
  (setv opts (parse-args [["-r" "--resolvers"
                           :type (argparse.FileType "r")
                           :help "包含dns解析服务器列表的文件,如果为空，则使用系统的dns解析服务器"]
                          ["-d" "--domains"
                           :nargs "?"
                           :type (argparse.FileType "r")
                           :default sys.stdin
                           :help "域名列表文件"]
                          ["-t" "--types"
                           :type rdtypes
                           :default "a,aaaa,mx,ns,txt,cname,soa"
                           :help "要查询的record类型,','分割 (default: %(default)s)"]
                          ["--save-empty"
                           :action "store_true"
                           :help "是否保存空查询结果 (default: %(default)s)"]
                          ["-e" "--timeout"
                           :type int
                           :default 60
                           :help "记录查询超时时间(秒) (default: %(default)s)"]
                          ["-v" "--verbose"
                           :nargs "?"
                           :type int
                           :default 0
                           :help "日志输出级别(0,1,2)　 (default: %(default)s)"]
                          ["-o" "--output-dir"
                           :type str
                           :default "./"
                           :nargs "?"
                           :help "输出域名查询信息的目录，每个域名保存一个文件,默认为当前目录"]
                          ["domain" :nargs "*" :help "域名列表"]
                          ]
                         (rest args)
                         :description "检测域名的所有查询记录"))
  (set-logging-level opts.verbose)

  (setv resolver (when opts.resolvers
                   (read-valid-lines opts.resolvers)))
  (setv domains  (read-nargs-or-input-file opts.domain opts.domains))

  (os.makedirs opts.output-dir :exist-ok True)
  (for [d domains]
    (setv r (get-records d
                         :resolver resolver
                         :types opts.types
                         :timeout opts.timeout))
    (when (or opts.save-empty
              (not (empty? r)))
      (with [w (-> (os.path.join opts.output-dir f"{d}.json")
                   (open :mode "w"))]
        (json.dump r w :indent 2 :sort-keys True))))

  (logging.info "over.")
  )
