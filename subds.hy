#!/usr/bin/env hy

(require [hy.extra.anaphoric [*]]
         [helpers [*]]
         )

(import requests
        json
        re
        os
        logging
        sys
        argparse
        time
        csv

        [bs4 [BeautifulSoup]]
        [datetime [datetime]]
        [retry [retry]]
        [fake-useragent [UserAgent]]
        [helpers [*]]
        [publicsuffix2 [get-public-suffix]]
        )

(setv ua (UserAgent :use-cache-server True ))
(setv proxy None #_{"http" "http://localhost:8080"
                    "https" "http://localhost:8080"})

(defn random-ua
  []
  "随机获取一个user-agent"
  ua.random)

(defn curr-times
  []
  "当前时间字符串"
  (-> (.now datetime)
      (.strftime "%Y-%m-%d")))

(defn parse-last-history-url
  [body]
  (some-> (BeautifulSoup body "lxml")
          (.select-one "div.history-item.col-md-4 a")
          (of "href")
          (->> (+ "https:"))))

(defn parse-table-rows
  [table]
  (lfor r (rest (.select table "tr"))
        (lfor c (rest (.select r "td"))
              (if c.img
                  (= "CloudFlare is on"
                     (of c.img "title"))
                  (.get-text c " " :strip True)))))

(defn parse-subdomains
  [body]
  (-> (BeautifulSoup body "lxml")
      (.select-one "table#result_table")
      parse-table-rows
      (->> (map #%(->> %1
                       (zip ["domain" "ip" "clould-flare"])
                       dict)))
      list))

(defn get-subds
  [domain]
  (logging.info "get subdomains for:%s" domain)
  (setv headers {"user-agent" (random-ua)})
  (setv s (requests.Session))
  (some-> (s.get
            f"https://subdomainfinder.c99.nl/scans/{(curr-times)}/{domain}"
            :headers headers :proxies proxy :verify False)
          (. text)
          (parse-last-history-url)
          (s.get :headers headers :proxies proxy :verify False)
          (. text)
          parse-subdomains))

(defn save-data
  [out-path data]
  (when (not (empty? data))
    (with [outf (open out-path "a" :newline "")]
      (-> (csv.DictWriter outf (-> (first data)
                                   (.keys)
                                   list))
          (.writerows data)))))

(defmain [&rest args]
  (logging.basicConfig :level logging.INFO
                       ;; :filename "app.log"
                       ;; :filemode "w"
                       :style "{"
                       :format "{asctime} [{levelname}] {filename}({funcName})[{lineno}] {message}")

  (setv opts (parse-args [["-d" "--domains" :type (argparse.FileType "r")
                           :help "包含域名列表的文件"]
                          ["-o" "--output" :type str
                           :default "out.csv"
                           :help "output file path"]
                          ["domain" :nargs "*" :help "要查找的域名"]]
                         (rest args)
                         :description "查找域名对应的所有子域名"))

  (setv domains  (if (opts.domains.isatty)
                     (if opts.domain
                         opts.domain
                         (read-valid-lines opts.domains))
                     (concat opts.domain
                             (read-valid-lines opts.domains))))
  (for [d domains]
    (some->> (get-public-suffix d)
             (get-subds)
             (filter #%(-> (of %1 "ip")
                           (!= "none")))
             list
             (save-data opts.output))
    (time.sleep 2))

  (logging.info "over!")
  )
