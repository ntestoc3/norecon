#!/usr/bin/env hy

(require [hy.extra.anaphoric [*]]
         [helpers [*]]
         )

(import os
        logging
        sys
        re
        json
        argparse
        subprocess
        validators
        tempfile
        ipaddress

        [datetime [datetime]]
        [qqwry [updateQQwry QQwry]]
        [helpers [*]]
        [event-bus [EventBus]]
        [screen [aquatone]]
        [publicsuffix2 [get-public-suffix]]
        )

(setv bus (EventBus))

(defn read-project-file
  [opts &rest paths]
  (setv fpath (os.path.join opts.project-dir #* paths))
  (when (os.path.exists fpath)
    (with [f (open fpath)]
      (json.load f))))

(defn read-ip
  [ip opts]
  (read-project-file opts "ip" f"{ip}.json"))

(defn read-whois
  [host opts]
  (read-project-file opts "whois" f"{host}.json"))

(defn read-domain
  [domain opts]
  (read-project-file opts "domain" f"{domain}.json"))

(defn read-record
  [domain opts]
  (read-project-file opts "record" f"{domain}.json"))

;;;; ip位置查询
(defn time-modify-delta
  [f]
  (->> (os.path.getmtime f)
       (datetime.fromtimestamp)
       (- (datetime.now))))

(setv ip-loc (QQwry))

(defn load-qqwry
  []
  (setv data-path (os.path.join (tempfile.gettempdir) "ip_qqwry.dat"))
  (when (not (and (os.path.exists data-path)
                  (< (-> (time-modify-delta data-path)
                         (. days))
                     30)))
    (updateQQwry data-path))
  (ip-loc.load-file data-path))

(defn get-location
  [ip]
  (->> (ip-loc.lookup ip)
       (str.join "-")))

;;; gen resolvers
(defn gen-resolvers
  [&optional [force-update False] [timeout 5] [reliablity 0.8]]
  "生成resolvers,返回resolver文件路径"
  (logging.info "gen resolvers")
  (setv data-path (os.path.join (tempfile.gettempdir) "resolvers"))
  (when (or force-update
            (not (and (os.path.exists data-path)
                      (< (-> (time-modify-delta data-path)
                             (. days))
                         1))))
    (subprocess.run ["./ns_resolvers.hy"
                     "-o" data-path
                     "-r" (str reliablity)
                     "-t" (str timeout)]
                    :encoding "utf-8"))
  data-path)


;;; event task
(with-decorator (bus.on "new:whois")
  (defn whois
    [target &optional opts]
    (logging.info "whois: %s" target)
    (setv out-dir (os.path.join opts.project-dir "whois"))
    (os.makedirs out-dir :exist-ok True)

    (setv out-path f"{(os.path.join out-dir target)}.json")
    (when (and (not opts.overwrite)
               (os.path.exists out-path))
      (logging.info "whois: %s already taken!" target)
      (return))

    (subprocess.run ["./nt_whois.hy"
                     "-o" out-path
                     target]
                    :encoding "utf-8")))

(with-decorator (bus.on "new:record-query")
  (defn domain-record-query
    [domains opts]
    (logging.info "record query: %s" domains)
    (setv out-dir (os.path.join opts.project-dir "record"))
    (os.makedirs out-dir :exist-ok True)

    (when (not opts.overwrite)
      (setv scan-domains (lfor d domains
                               :if (-> (os.path.join out-dir f"{d}.json")
                                       os.path.exists
                                       not)
                               d)))

    (unless (empty? scan-domains)
      (subprocess.run ["./ns_records.hy"
                       #* (if opts.resolvers
                              ["-r" opts.resolvers]
                              [])
                       "-o" out-dir
                       #* scan-domains
                       ]
                      :encoding "utf-8"))

    (setv ips [])
    (for [d domains]
      (setv rs (read-record d opts))
      (when rs
        (bus.emit "new:screenshot" d opts)
        (->> rs
             (filter #%(= "A" (of %1 "type")))
             (map #%(of %1 "result"))
             cat
             (+= ips))))
    (bus.emit "new:ips" (set ips) opts)))

(with-decorator (bus.on "new:screenshot")
  (defn screen-shot
    [host opts &optional ports]
    (logging.info "screenshot: %s" host)
    (setv out-dir (os.path.join opts.project-dir "screen"))
    (os.makedirs out-dir :exist-ok True)

    (setv out-path f"{(os.path.join out-dir host)}.json")
    (when (and (os.path.exists out-path)
               (not opts.overwrite))
      (logging.info "screenshot: %s already taken!" host)
      (return))

    (aquatone host
              :out-path out-dir
              :ports ports
              :timeout opts.screenshot-timeout
              :opts ["-report=false"
                     "-similar=false"
                     "-session-out-name" f"{host}.json"
                     ])))

(defn cdn-ip?
  [ip opts]
  "检测是否为cdn ip"
  (setv net-name (-> (read-whois ip opts)
                     (get-in ["network" "name"])))
  (in net-name ["CLOUDFLARENET"
                "AKAMAI"
                "CHINANETCENTER" ;; 网宿
                ]))

(with-decorator (bus.on "new:ips")
  (defn ip-scan
    [ips opts]
    (logging.info "ip-scan: %s" ips)
    (setv out-dir (os.path.join opts.project-dir "ip"))
    (os.makedirs out-dir :exist-ok True)

    (defn send-screenshot
      [ip]
      (setv info (read-ip ip opts))
      (when info
        (bus.emit "new:screenshot" ip opts
                  :ports (some->> (.get info "ports")
                                  (map #%(.get %1 port))
                                  (str.join ",")))))

    (for [ip ips]
      (when (-> (ipaddress.ip-address ip)
                (. is-global)
                not)
        (logging.warn "ip scan 跳过非公开地址:%s." ip)
        (continue))

      (setv out-path f"{(os.path.join out-dir ip)}.json")
      (when (and (not opts.overwrite)
                 (os.path.exists out-path))
        (logging.info "ip scan %s already scaned!" ip)
        (send-screenshot ip)
        (continue))

      (bus.emit "new:whois" ip opts)

      (when (not (and (cdn-ip? ip opts)
                      opts.scan-cdn-ip))
        (subprocess.run ["./nmap.hy"
                         "-t" (str opts.ip-scan-timeout)
                         "-r" (str opts.masscan-rate)
                         "-d" out-dir
                         ip
                         ]
                        :encoding "utf-8")

        (send-screenshot ip)))))

(with-decorator (bus.on "new:domain")
  (defn domain
    [root-domain opts]
    (logging.info "top level domain scan: %s" root-domain)
    (bus.emit "new:whois" root-domain opts)

    (setv out-dir (os.path.join opts.project-dir "domain"))
    (os.makedirs out-dir :exist-ok True)

    (setv out-path f"{(os.path.join out-dir root-domain)}.json")
    (defn send-record-query
      []
      (with [pf (open out-path)]
        (->2> (read-valid-lines pf)
              (bus.emit "new:record-query" opts))))
    (when (and (not opts.overwrite)
               (os.path.exists out-path))
      (logging.info "top level domain scan %s already scaned!" root-domain)
      (send-record-query)
      (return))

    (setv [_ amass-out] (tempfile.mkstemp ".txt" f"amass_{root-domain}_"))
    (subprocess.run ["./amass.hy"
                     "-t" (str opts.amass-timeout)
                     "-o" amass-out
                     root-domain]
                    :encoding "utf-8")

    (setv [_ subds-out] (tempfile.mkstemp ".txt" f"subds_{root-domain}_"))
    (subprocess.run ["./subds.hy"
                     "-o" subds-out
                     root-domain]
                    :encoding "utf-8")

    (with [outf (open out-path "w")
           r1 (open amass-out)
           r2 (open subds-out)]
      (-> (concat (read-valid-lines r1)
                  (read-valid-lines r2))
          (->> (map #%(-> (str.lower %1)
                          (str.strip "."))))
          set
          (->> (str.join "\n"))
          (outf.write)))

    (os.unlink amass-out)
    (os.unlink subds-out)

    (send-record-query)))

(comment

  (defn get-ip-net-name
    [ip opts]
    (bus.emit "new:whois" ip opts)
    (-> (read-whois ip opts)
        (get-in ["network" "name"])))

  (import [attrdict [AttrDict :as adict]])

  (setv opts (adict {"project_dir" "hackerone"
                     "resolvers" "./resolv"
                     "amass_timeout" 1
                     "ip-scan-timeout" 500
                     "masscan-rate" 1000
                     "screenshot_timeout" 1000
                     "scan_cdn_ip" False}))

  (domain "hackerone.com" opts)
  )

;;;;;; 验证
(defn valid-cidr?
  [ip]
  (setv grp (str.split ip "/"))
  (if (= (len grp) 2)
      (do (setv [ip subnet] grp)
          (and (validators.ipv4 ip)
               (<= 0 (int subnet) 32)))
      False))

(defn valid-ip-range?
  [ip]
  (setv grp (str.split ip "-"))
  (if (= (len grp) 2)
      (do (setv [ip ip-end] grp)
          (and (validators.ipv4 ip)
               (validators.ipv4 ip-end)))
      False))

(defn valid-ip-target?
  [target]
  (or (validators.ipv4 target)
      (valid-cidr? target)
      (valid-ip-range? target)))

(defn domain?
  [domain]
  (validators.domain domain))

(defn root-domain?
  [domain]
  "是否为一级域名"
  (= domain
     (get-public-suffix domain)))

(defmain [&rest args]
  (logging.basicConfig :level logging.INFO
                       :handlers [(logging.FileHandler :filename "recon_app.log")
                                  (logging.StreamHandler sys.stderr)]
                       :style "{"
                       :format "{asctime} [{levelname}] {filename}({funcName})[{lineno}] {message}")

  (setv opts (parse-args [["--amass-timeout"
                           :type int
                           :default 5
                           :help "amass扫描超时时间(分) (default: %(default)s)"]
                          ["--ip-scan-timeout"
                           :type int
                           :default 600
                           :help "ip扫描超时时间(秒) (default: %(default)s)"]
                          ["--screenshot-timeout"
                           :type int
                           :default 1000
                           :help "屏幕快照超时时间(秒) (default: %(default)s)"]
                          ["--masscan-rate"
                           :type int
                           :default 1000
                           :help "masscan扫描速率 (default: %(default)s)"]
                          ["--scan-cdn-ip"
                           :type bool
                           :default False
                           :help "是否对cdn ip进行端口扫描 (default: %(default)s)"]
                          ["--overwrite"
                           :type bool
                           :default False
                           :help "是否强制重新扫描(如果为False,则扫描过的项目不再重新扫描) (default: %(default)s)"]
                          ["-p" "--project-dir"
                           :type str
                           :required True
                           :help "项目根目录"]
                          ["-t" "--targets"
                           :nargs "?"
                           :type (argparse.FileType "r")
                           :default sys.stdin
                           :help "输入的目标"]
                          ["target" :nargs "*" :help "要扫描的目标，可以是域名或ip地址"]
                          ]
                         (rest args)
                         :description "针对目标进行recon"))

  (setv targets (read-nargs-or-input-file opts.target opts.targets))

  (->> (gen-resolvers)
       (setv opts.resolvers))

  (defn network->ips
    [n]
    (->> (ipaddress.ip-network n)
         (map str)
         list))

  (for [t targets]
    (cond
      [(domain? t)

       (if (root-domain? t)
           (bus.emit "new:domain" t opts)
           (bus.emit "new:record-query" t opts))]

      [(valid-ip-range? t)

       (as-> (str.split t "-") [start end]
             (->2> (ipaddress.summarize-address-range
                     (ipaddress.ip-address start)
                     (ipaddress.ip-address end))
                   (map network->ips)
                   cat
                   (bus.emit "new:ips" opts)))]

      [(valid-cidr? t)

       (->2> (network->ips t)
             (bus.emit "new:ips" opts))]

      [True
       (logging.warning "not valid target: %s" t)]))

  (logging.info "over!")
  )
