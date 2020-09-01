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
  (some-> (BeautifulSoup body "lxml")
          (.find-all "table" :id (re.compile ".*result.*"))
          first
          parse-table-rows
          (->> (map first))
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

(defmainf [&rest args]
  (setv opts (parse-args [["-d" "--domains" :type (argparse.FileType "r")
                           :default sys.stdin
                           :help "包含域名列表的文件"]
                          ["-o" "--output"
                           :nargs "?"
                           :type (argparse.FileType "w")
                           :default sys.stdout
                           :help "输出文件名"]
                          ["-v" "--verbose"
                           :nargs "?"
                           :type int
                           :default 0
                           :help "日志输出级别(0,1,2)　 (default: %(default)s)"]
                          ["domain" :nargs "*" :help "要查找的域名"]]
                         (rest args)
                         :description "查找域名对应的所有子域名"))

  (set-logging-level opts.verbose)

  (setv domains (->> (read-nargs-or-input-file opts.domain opts.domains)
                     (map get-public-suffix)
                     set))

  (for [d domains]
    (some->> (get-subds d)
             (str.join "\n")
             (opts.output.write))
    (time.sleep 2))

  (logging.info "over!")
  )
