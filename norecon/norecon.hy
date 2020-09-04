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
        [helpers [*]]
        [event-bus [EventBus]]
        [noscreen [aquatone]]
        [publicsuffix2 [get-public-suffix]]
        [glob [glob]]
        [project [*]]
        [shutil [which]]
        [fnmatch [fnmatch]]
        [dns [resolver reversename]]
        [iploc [get-location]]
        )

(setv bus (EventBus))

(setv resolvers-bin "noresolvers"
      whois-bin "nowhois"
      records-bin "norecords"
      nmap-bin "nonmap"
      amass-bin "noamass"
      subfinder-bin "nosubsfinder"
      )

;;; gen resolvers
(defn gen-resolvers
  [&optional [force-update False] [timeout 5] [reliablity 0.8] [verbose 0]]
  "生成resolvers,返回resolver文件路径"
  (logging.info "gen resolvers")
  (setv data-path (os.path.join (tempfile.gettempdir) "resolvers"))
  (when (or force-update
            (not (and (os.path.exists data-path)
                      (< (-> (time-modify-delta data-path)
                             (. days))
                         1))))
    (subprocess.run [resolvers-bin
                     "-o" data-path
                     "-r" (str reliablity)
                     "-v" (str verbose)
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

    (subprocess.run [whois-bin
                     "-o" out-path
                     "-v" (str opts.verbose)
                     target]
                    :encoding "utf-8")))

(with-decorator (bus.on "new:record-query")
  (defn domain-record-query
    [domains opts]
    (logging.info "record query: %s" domains)
    (setv out-dir (os.path.join opts.project-dir "record"))
    (os.makedirs out-dir :exist-ok True)

    (setv scan-domains
          (lfor d domains
                ;; 没有扫描过或进行覆盖
                :if (or (not (-> (os.path.join out-dir f"{d}.json")
                                 (os.path.exists)))
                        opts.overwrite)
                ;; 没有被排除
                :if (not (exclude? d))
                d))

    (unless (empty? scan-domains)
      (logging.info "record query, real scan: %s" scan-domains)
      (subprocess.run [records-bin
                       #* (if opts.resolvers
                              ["-r" opts.resolvers]
                              [])
                       "--save-empty"
                       "-o" out-dir
                       "-v" (str opts.verbose)
                       #* scan-domains
                       ]
                      :encoding "utf-8"))

    (setv ips [])
    (for [d domains]
      (setv rs (read-record d opts.project-dir))
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

(with-decorator (bus.on "new:screenshot:html")
  (defn screen-shot-html
    [opts]
    (logging.info "generate screenshot html.")
    (setv out-dir (os.path.join opts.project-dir "screen"))
    (os.makedirs out-dir :exist-ok True)

    (setv session-name f"{opts.screen-session}.json")
    (setv sessions (->> (glob f"{out-dir}/*.json")
                        (filter #%(not (= session-name
                                          (os.path.basename %1))))
                        (str.join ",")))
    (unless (empty? sessions)
      (aquatone "\n"
                :out-path out-dir
                :timeout opts.screenshot-timeout
                :opts ["-session-out-name" session-name
                       "-report-out-name" f"{opts.screen-session}.html"
                       "-combine-sessions" sessions]))))

(defn get-ip-host
  [ip]
  "根据ip地址反查域名"
  (try
    (some-> (reversename.from-address ip)
            (resolver.query "PTR")
            (first)
            str)
    (except [Exception]
      "")))

(defn get-net-name
  [ip opts]
  "获取`ip`的网络名"
  (some-> (read-whois ip opts.project-dir)
          (get-in ["network" "name"])))

(setv cdn-names {"CLOUDFLARENET" "Cloudflare"
                 "AKAMAI" "Akamai"
                 "CHINANETCENTER" "ChinaNetCenter" ;;　网宿科技
                 "AMAZO-CF" "CloudFront"})

(defn cdn-name
  [net-name]
  "根据网络名获取对应的cdn名称"
  (cdn-names.get net-name))

(defn cdn-ip?
  [ip opts]
  "检测是否为cdn ip"
  (-> (get-net-name ip opts)
      cdn-name
      none?
      not))

(with-decorator (bus.on "new:ips")
  (defn ip-scan
    [ips opts]
    (logging.info "ip-scan: %s" ips)
    (setv out-dir (os.path.join opts.project-dir "ip"))
    (os.makedirs out-dir :exist-ok True)

    (defn send-screenshot
      [ip]
      (some-> (read-ip ip opts.project-dir)
              (.get "ports")
              (some->> (map #%(.get %1 "port"))
                       (str.join ",")
                       (bus.emit "new:screenshot" ip opts
                                 :ports ))))

    (for [ip ips]
      ;; 检测是否已经扫描过
      (setv out-path f"{(os.path.join out-dir ip)}.json")
      (when (and (not opts.overwrite)
                 (os.path.exists out-path))
        (logging.info "ip scan %s already scaned!" ip)
        (send-screenshot ip)
        (continue))

      ;; 检测是否排除
      (when (exclude? ip)
        (logging.info "ip scan %s exclude!" ip)
        (continue))

      ;; 检测私有地址
      (when (-> (ipaddress.ip-address ip)
                (. is-global)
                not)
        (with [w (open out-path "w")]
          (json.dump {"ip" ip
                      "location" (get-location ip)}
                     w :ensure-ascii False :indent 2 :sort-keys True :default str))
        (logging.warn "ip scan 跳过非公开地址:%s." ip)
        (continue))

      ;; 注意必须放在cdn ip检测之前执行whois，否则无法正常检测
      (bus.emit "new:whois" ip opts)

      ;; 检测cdn ip
      (setv ip-net-name (get-net-name ip opts))
      (setv ip-info {"ip" ip
                     "host" (get-ip-host ip)
                     "location" (get-location ip)
                     "net-name" ip-net-name
                     "cdn-type" (cdn-name ip-net-name)})

      ;; 写入基本信息进行占位，没有扫描结果的ip不再扫描
      (with [w (open out-path "w")]
        (json.dump ip-info w :ensure-ascii False :indent 2 :sort-keys True :default str))

      (when (and (cdn-ip? ip opts)
                 (not opts.scan-cdn-ip))
        (logging.info "ip service scan skip cdn ip:%s." ip)
        (continue))

      (logging.info "ip service scan:%s" ip)
      (subprocess.run [nmap-bin
                       "-t" (str opts.ip-scan-timeout)
                       "-r" (str opts.masscan-rate)
                       "-d" out-dir
                       "-v" (str opts.verbose)
                       ip
                       ]
                      :encoding "utf-8")

      (-> (read-ip ip opts.project-dir)
          (ip-info.update))

      (with [w (open out-path "w")]
        (json.dump ip-info w :ensure-ascii False :indent 2 :sort-keys True :default str))
      (send-screenshot ip))))

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
      (some->2> (read-domain root-domain opts.project-dir)
                (bus.emit "new:record-query" opts)))
    (when (and (not opts.overwrite)
               (os.path.exists out-path))
      (logging.info "top level domain scan %s already scaned!" root-domain)
      (send-record-query)
      (return))

    ;; amass查询
    (setv [_ amass-out] (tempfile.mkstemp ".txt" f"amass_{root-domain}_"))
    (subprocess.run [amass-bin
                     "-t" (str opts.amass-timeout)
                     "-o" amass-out
                     "-v" (str opts.verbose)
                     root-domain]
                    :encoding "utf-8")

    ;; 使用网页查询
    (setv [_ subds-out] (tempfile.mkstemp ".txt" f"subds_{root-domain}_"))
    (subprocess.run [subfinder-bin
                     "-o" subds-out
                     "-v" (str opts.verbose)
                     root-domain]
                    :timeout 300
                    :encoding "utf-8")

    ;; 保存结果
    (with [outf (open out-path "w")
           r1 (open amass-out)
           r2 (open subds-out)]
      (-> (concat (read-valid-lines r1)
                  (read-valid-lines r2))
          (->> (map #%(-> (str.lower %1)
                          (str.strip "."))))
          set
          list
          (json.dump outf :indent 2 :sort-keys True)))

    (os.unlink amass-out)
    (os.unlink subds-out)

    (send-record-query)))

(comment

  (defn get-ip-net-name
    [ip opts]
    (bus.emit "new:whois" ip opts)
    (-> (read-whois ip opts.project-dir)
        (get-in ["network" "name"])))

  (import [attrdict [AttrDict :as adict]])

  (setv opts (adict {"project_dir" "../hackerone"
                     "resolvers" "./resolv"
                     "amass_timeout" 1
                     "ip_scan_timeout" 500
                     "masscan_rate" 1000
                     "screen_session" "screen"
                     "overwrite" False
                     "verbose" 2
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

(defn check-bin
  [binary]
  (as-> (which binary) p
        (if p
            (do (logging.info "%s :%s" binary p)
                p)
            (raise (FileNotFoundError binary)))))

(setv exclude-hosts [])

(defn exclude? [host]
  "是否被排除"
  (for [e exclude-hosts]
    (when (fnmatch host e)
      (return True)))
  (return False))

(defmainf [&rest args]
  (setv opts (parse-args [["--amass-timeout"
                           :type int
                           :default 60
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
                           :action "store_true"
                           :help "是否对cdn ip进行端口扫描 (default: %(default)s)"]
                          ["--overwrite"
                           :action "store_true"
                           :help "是否强制重新扫描(如果为False,则扫描过的项目不再重新扫描) (default: %(default)s)"]
                          ["-ss" "--screen-session"
                           :type str
                           :default "screen"
                           :help "输出屏幕快照的session文件名 (default: %(default)s)"]
                          ["-e" "--exclude"
                           :nargs "?"
                           :type (argparse.FileType "r")
                           :default None
                           :help "包含排除列表的文件,可以是域名或ip,支持glob格式匹配(*?)"]
                          ["-p" "--project-dir"
                           :type str
                           :required True
                           :help "项目根目录"]
                          ["-t" "--targets"
                           :nargs "?"
                           :type (argparse.FileType "r")
                           :default sys.stdin
                           :help "输入的目标"]
                          ["-v" "--verbose"
                           :nargs "?"
                           :type int
                           :default 0
                           :help "日志输出级别(0,1,2)　 (default: %(default)s)"]
                          ["target" :nargs "*" :help "要扫描的目标，可以是域名或ip地址"]
                          ]
                         (rest args)
                         :description "针对目标进行recon"))
  (set-logging-level opts.verbose)

  (for [x ["amass"
           "aquatone"
           "masscan"
           "nmap"
           resolvers-bin
           whois-bin
           records-bin
           nmap-bin
           amass-bin
           subfinder-bin]]
    (check-bin x))

  (setv targets (read-nargs-or-input-file opts.target opts.targets))

  (when opts.exclude
    (setv exclude-hosts (read-valid-lines opts.exclude)))

  (->> (gen-resolvers :verbose opts.verbose)
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

      [(validators.ipv4 t)
       (bus.emit "new:ips" [t] opts)]

      [True
       (logging.warning "not valid target: %s" t)]))

  (bus.emit "new:screenshot:html" opts)

  (logging.info "over!")
  )
