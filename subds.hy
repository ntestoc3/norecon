#!/usr/bin/env hy

(require [hy.extra.anaphoric [*]])
(require [helpers [*]])

(import [bs4 [BeautifulSoup]])
(import requests)
(import json)
(import re)
(import os)
(import logging)
(import sys)
(import argparse)
(import [datetime [datetime]])
(import [retry [retry]])
(import [fake-useragent [UserAgent]])
(import [helpers [*]])

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
  (-> (BeautifulSoup body "lxml")
      (.select-one "div.history-item a")
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

(defn get-subs
  [domain]
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

(defmain [&rest args]
  (logging.basicConfig :level logging.INFO
                       :filename "app.log"
                       :filemode "w"
                       :style "{"
                       :format "{asctime} [{levelname}] {filename}({funcName})[{lineno}] {message}")

  (setv ags (parse-args [["-d" "--domains-file" :type (argparse.FileType "r")
                          :help "file contains domains"]
                         ["domain" :nargs "+" :help "root domain for subdomain search"]]
                        (rest args)
                        :description "find subdomains for root domain"))
  (logging.info "args:%s" ags)

  (logging.info "over!")
  )
