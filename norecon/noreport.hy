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
      (render->file template
                    arg
                    (os.path.join save-path f"{target}{postfix}.md")))))

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

(defmainf [&rest args]
  (setv opts (parse-args [["-v" "--verbose"
                           :nargs "?"
                           :type int
                           :default 0
                           :help "日志输出级别(0,1,2)　 (default: %(default)s)"]
                          ["-e" "--gen-empty"
                           :action "store_true"
                           :help "是否生成空项 (default: %(default)s)"]
                          ["-c" "--clear"
                           :action "store_true"
                           :help "删除生成的报告 (default: %(default)s)"]
                          ["project_dir"  :help "要生成报告的项目根目录"]]
                         (rest args)
                         :description "生成项目报告"))

  (set-logging-level opts.verbose)

  (if opts.clear
      (clear-reports opts.project-dir)
      (doto opts.project-dir
            (render-whois :gen-empty opts.gen-empty)
            (render-domain :gen-empty opts.gen-empty)
            (render-record :gen-empty opts.gen-empty)
            (render-ip :gen-empty opts.gen-empty)))

  (logging.info "over!")
  )
