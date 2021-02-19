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
        validators
        itertools

        [sqlite-utils [Database]]
        [datetime [datetime]]
        [helpers [*]]
        [project [*]]
        [shutil [copy]]
        [jinja2 [Environment
                 FileSystemLoader
                 PackageLoader]]
        [glob [glob]])

(setv curr-dir (try --file--
                    (os.path.dirname --file--)
                    (except [NameError]
                      (os.getcwd))))

(setv env (Environment :loader (FileSystemLoader (os.path.join curr-dir "templates"))
                       :trim-blocks True
                       :lstrip-blocks True))

(defn render->file
  [template-name data filepath]
  (with [w (open filepath "w")]
    (-> (env.get-template template-name)
        (.render data)
        (w.write))))

(defn render-project-notes
  [project-dir item-dir template get-arg-fn &optional [postfix ""] [gen-empty False]]
  "`get-arg-fn` 生成传递给模板参数的函数:接受参数为target(当前要生成的项目名)"
  (setv save-path (os.path.join project-dir item-dir))
  (for [f (glob (os.path.join project-dir item-dir "*.json"))]
    (setv target (fstem f))
    (setv arg (get-arg-fn target))
    (when (or gen-empty
              (not (or (none? (of arg "data"))
                       (empty? (of arg "data")))))
      (try (render->file template
                         arg
                         (os.path.join save-path f"{target}{postfix}.md"))
           (except [e Exception]
             (logging.exception "render-notes template:%s, item:%s."
                                template
                                f))))))

(defn gen-screen-info
  [target project-dir &kwargs opts]
  (some-> (read-screen-session target project-dir)
          (.get "pages")
          (.items)
          (as-> $
                (lfor [k d] $
                      :do (do
                            (setv (of d "target") k)
                            (as-> (.get d "screenshotPath") spath
                                  (when spath
                                    (-> (os.path.join project-dir "screen" spath)
                                        (os.path.relpath (os.path.join project-dir "ip"))
                                        (->> (setv (of d "screenshotPath")))))))
                      d))))

(defn render-whois
  [project-dir &kwargs opts]
  (render-project-notes :project-dir project-dir
                        #** opts
                        :item-dir "whois"
                        :template "whois.md"
                        :postfix "_whois"
                        :get-arg-fn (fn [target]
                                      {"data" (read-whois target project-dir)
                                       "target" target})))

(defn gen-domain-data
  [target project-dir]
  {"data" (lfor d (read-domain target project-dir)
                {"domain" d
                 "http-info" (some->2> (gen-screen-info d project-dir)
                                       (lfor info
                                             {"status" (.get info "status")
                                              "title" (.get info "pageTitle")
                                              "url" (.get info "url")
                                              "tags" (.get info "tags")}))
                 "ip-info" (some->2> (some-> (read-record d project-dir)
                                             (->> (filter #%(= (.get %1 "type") "A")))
                                             first
                                             (.get "result"))
                                     (lfor ip
                                           (merge-with #%(return %2)
                                             (read-ip ip project-dir)
                                             {"ip" ip})))})
   "target" target})

(defn render-domain
  [project-dir &kwargs opts]
  (render-project-notes :project-dir project-dir
                        #** opts
                        :item-dir "domain"
                        :template "domain.md"
                        :postfix "_domain"
                        :get-arg-fn #%(gen-domain-data %1 project-dir)))



(defn render-ip
  [project-dir &kwargs opts]
  (render-project-notes :project-dir project-dir
                        #** opts
                        :item-dir "ip"
                        :template "ip.md"
                        :get-arg-fn (fn [target]
                                      {"data" (read-ip target project-dir)
                                       "screen" (gen-screen-info target project-dir)
                                       "target" target})))

(defn render-record
  [project-dir &kwargs opts]
  (render-project-notes :project-dir project-dir
                        #** opts
                        :item-dir "record"
                        :template "record.md"
                        :get-arg-fn (fn [target]
                                      {"data" (read-record target project-dir)
                                       "screen" (gen-screen-info target project-dir)
                                       "target" target})))

(defn clear-reports
  [project-dir]
  (for [f (glob (os.path.join project-dir "*" "*.md"))]
    (os.unlink f)))

(defn insert-table
  [db table data &kwargs kwargs]
  (-> (of db table)
      (.insert-all data #** kwargs)))

(defn save-project-items
  [db project-dir item-dir gen-data-fn &optional table-name column-order]
  "`gen-data-fn` 生成插入数据库的记录行:接受参数为target(当前要生成的项目名),
                 返回行列表"
  (setv table-name (or table-name item-dir))
  (logging.info f"save project {project-dir} {item-dir} to table {table-name}.")
  (setv save-path (os.path.join project-dir item-dir))

  (for [datas (->> (os.path.join project-dir item-dir "*.json")
                   (glob)
                   (map (fn [f]
                          (-> (fstem f)
                              (gen-data-fn))))
                   (filter (fn [data]
                             (not (or (none? data)
                                      (empty? data)))))
                   (split-every 200))]
    (setv rows (cat datas))
    (logging.info "insert rows:%d" (len rows))
    (insert-table db table-name rows :alter True :column-order column-order)))

(defn ip-whois->db
  [db project &optional opts]
  (save-project-items db
                      project
                      "whois"
                      (fn [target]
                        (when (or (validators.ipv4 target)
                                  (validators.ipv6 target))
                          (setv info (read-whois target project))
                          (setv net-info (-> (info.get "network" {})
                                             (select-keys ["cidr"
                                                           "name"
                                                           "start_address"
                                                           "end_address"])))
                          [(doto (select-keys info ["asn"
                                                    "asn_cidr"
                                                    "asn_date"
                                                    "asn_country_code"
                                                    "asn_registry"
                                                    "entities"])
                                 (.update net-info)
                                 (assoc "ip" target))]))
                      :table-name "ip_whois"
                      :column-order ["ip"
                                     "cidr"
                                     "name"
                                     "start_address"
                                     "end_address"]))

(defn domain-whois->db
  [db project &optional opts]
  (save-project-items db
                      project
                      "whois"
                      (fn [target]
                        (when (validators.domain target)
                          (setv info (read-whois target project))
                          [(doto (select-keys info ["country"
                                                    "org"
                                                    "registrar"
                                                    "updated_date"
                                                    "creation_date"
                                                    "expiration_date"
                                                    "name_servers"])
                                 (assoc "domain" target))]))
                      :table-name "domain_whois"
                      :column-order ["domain"
                                     "org"
                                     "registrar"
                                     "country"
                                     "updated_date"]))

(defn record->db
  [db project &optional opts]
  (save-project-items db
                      project
                      "record"
                      (fn [target]
                        (setv items [])
                        (for [r (read-record target project)]
                          (if (= "A" (get r "type"))
                              (for [ip (get r "result")]
                                (setv r1 (r.copy))
                                (assoc r1 "ip" ip)
                                (items.append r1))
                              (items.append r)))
                        items)
                      :column-order ["name" "type" "ip" "canonical-name" "result"]))

(defn ip->db
  [db project &optional opts]
  (save-project-items db
                      project
                      "ip"
                      (fn [target]
                        (setv info (read-ip target project))
                        (when info
                          (.pop info "ports" None)
                          (when-not (info.get "host" None)
                            (assoc info "host" None))
                          [info]))
                      :column-order ["ip" "net-name" "host" "cdn-type" "location"]))

(defn ports->db
  [db project &optional opts]
  (save-project-items db
                      project
                      "ip"
                      (fn [target]
                        (lfor port (-> (read-ip target project)
                                       (.get "ports" []))
                              (doto (dflatten port)
                                    (assoc "ip" target))))
                      :column-order ["ip"
                                     "port"
                                     "protocol"
                                     "service_type"
                                     "service_product"
                                     "service_version"
                                     "service_extra"
                                     "service_device-type"
                                     "service_finger-print"]
                      :table-name "ports"))

(defn screen->db
  [db project &optional opts]
  (setv server (if opts opts.file-server ""))
  (setv file-server-path f"{server}/{(fstem project)}/screen")
  (defn fix-path
    [path]
    (when path
      f"{file-server-path}/{path}"))
  (save-project-items db
                      project
                      "screen"
                      (fn [target]
                        (when-not (= target "screen")
                                  (setv screen (read-screen-session target project))
                                  (lfor page (-> (screen.get "pages" {})
                                                 (.values))
                                        (do (setv r (select-keys page ["url"
                                                                       "status"
                                                                       "pageTitle"
                                                                       "tags"
                                                                       "headersPath"
                                                                       "bodyPath"
                                                                       "screenshotPath"]))
                                            (assoc r "tags"
                                                   (some->> (r.get "tags" None)
                                                            (map (fn [tag]
                                                                   (tag.get "text" None)))
                                                            (str.join " | ")))
                                            (assoc r
                                                   "domain" None
                                                   "ip" None
                                                   "headersPath" (fix-path (r.get "headersPath"))
                                                   "bodyPath" (fix-path (r.get "bodyPath"))
                                                   "screenshotPath" (fix-path (r.get "screenshotPath")))
                                            (if (validators.domain target)
                                                (assoc r "domain" target)
                                                (assoc r "ip" target))
                                            r))))
                      :column-order ["domain"
                                     "ip"
                                     "url"
                                     "status"
                                     "tags"
                                     "pageTitle"
                                     "headersPath"
                                     "bodyPath"
                                     "screenshotPath"]))

(defn project->db
  [project &optional db-path opts]
  (setv proj-name (fstem project))
  (setv db-path (or db-path
                    (os.path.join project f"{proj-name}.db")))
  (print f"writting project info to sqlite3 db:{db-path}")
  (setv db (Database db-path :recreate True))

  ;; 保存表
  (ip-whois->db db project :opts opts)
  (domain-whois->db db project :opts opts)
  (record->db db project :opts opts)
  (ip->db db project :opts opts)
  (ports->db db project :opts opts)
  (screen->db db project :opts opts)

  ;; 添加约束，方便数据关联
  (.add-foreign-key (of db "record") "name" "screen" "domain" :ignore True)
  (.add-foreign-key (of db "record") "ip" "ip" "ip" :ignore True)

  (.add-foreign-key (of db "ip") "ip" "ports" "ip" :ignore True)

  (.add-foreign-key (of db "ports") "ip" "ip" "ip" :ignore True)

  (.add-foreign-key (of db "screen") "domain" "record" "name" :ignore True)
  (.add-foreign-key (of db "screen") "ip" "ip" "ip" :ignore True)

  (.add-foreign-key (of db "ip_whois") "ip" "ip" "ip" :ignore True)
  (.add-foreign-key (of db "domain_whois") "domain" "record" "name" :ignore True)
  db)

(require [hy.contrib.profile [profile/calls]])
(defmainf [&rest args]
  (setv opts (parse-args [["-v" "--verbose"
                           :nargs "?"
                           :type int
                           :default 0
                           :const 1
                           :help "日志输出级别(0,1,2) (default: %(default)s)"]
                          ["-e" "--gen-empty"
                           :action "store_true"
                           :help "是否生成空项 (default: %(default)s)"]
                          ["-d" "--db-file"
                           :help "保存的数据库文件名,如果不指定，则数据库文件名为:{项目文件名}.db"]
                          ["-t" "--type"
                           :default "md"
                           :type str
                           :choices ["md" "sqlite"]
                           :nargs "?"
                           :help "生成的报告类型 (default: %(default)s)"]
                          ["-s" "--file-server"
                           :default "http://localhost"
                           :help "文件服务器地址，用于sqlite中screen表的静态文件访问 (default: %(default)s)"
                           ]
                          ["-c" "--clear"
                           :action "store_true"
                           :help "删除生成的报告,仅针对md报告 (default: %(default)s)"]
                          ["project_dir"  :help "要生成报告的项目根目录"]]
                         (rest args)
                         :description "生成项目报告"))

  (set-logging-level opts.verbose)

  (cond
    [opts.clear
     (clear-reports opts.project-dir)]

    [(= opts.type "md")
     (doto opts.project-dir
           (render-whois :gen-empty opts.gen-empty)
           (render-domain :gen-empty opts.gen-empty)
           (render-record :gen-empty opts.gen-empty)
           (render-ip :gen-empty opts.gen-empty))]

    [(= opts.type "sqlite")
     #_(profile/calls (project->db opts.project-dir
                                 :db-path opts.db-file
                                 :opts opts))
     (project->db opts.project-dir
                  :db-path opts.db-file
                  :opts opts)]

    [True
     (logging.error "unsupport type:%s" opts.type)])

  (logging.info "over!")
  )

