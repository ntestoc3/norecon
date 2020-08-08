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
(setv proxy {"http" "http://localhost:8080"
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
  (with [outf (open out-path "a" :newline "")]
    (-> (csv.DictWriter outf (-> (first data)
                                 (.keys)
                                 list))
        (.writerows data))))


(defmain [&rest args]
  (logging.basicConfig :level logging.INFO
                       ;; :filename "app.log"
                       ;; :filemode "w"
                       :style "{"
                       :format "{asctime} [{levelname}] {filename}({funcName})[{lineno}] {message}")

  (setv opts (parse-args [["-df" "--domains-file" :type (argparse.FileType "r")
                           :help "file contains domains"]
                          ["-o" "--output" :type str
                           :default "out.csv"
                           :help "output file path"]
                          ["domain" :nargs "+" :help "root domain for subdomain search"]]
                         (rest args)
                         :description "find subdomains for root domain"))

  (when opts.domains-file
    (+= opts.domain (-> (opts.domains-file.read)
                        (.splitlines)))
    (opts.domains-file.close))

  (for [d opts.domain]
    (some->> (get-public-suffix d)
             (get-subds)
             (filter #%(-> (of %1 "ip")
                           (!= "none")))
             (save-data opts.output))
    (time.sleep 2))

  (logging.info "over!")
  )
