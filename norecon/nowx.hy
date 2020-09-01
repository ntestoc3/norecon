#!/usr/bin/env hy

(require [hy.extra.anaphoric [*]]
         [helpers [*]]
         )

(import os
        logging
        sys
        requests
        argparse
        json
        pprint
        datetime

        [retry [retry]]
        [helpers [*]]
        [pathlib [Path]]
        [configparser [ConfigParser NoSectionError]]
        [enum [Enum]]
        )

(setv CONFIG_FILE ".nowx.cfg")

(defn read-config [&optional [section "DEFAULT"]]
  (setv config-path (os.path.join (Path.home) CONFIG_FILE))
  (when (os.path.isfile config-path)
    (try (-> (ConfigParser)
             (doto (.read config-path))
             (of section)
             dict)
         (except [NoSectionError]
           (logging.warning "%s no [DEFAULT] section.")))))

(defn save-config [m &optional [section "DEFAULT"]]
  (setv config-path (os.path.join (Path.home) CONFIG_FILE))
  (with [w (open config-path "w")]
    (setv cfg (ConfigParser))
    (setv (of cfg section) m)
    (cfg.write w)))

(defn make-qrcode
  [token &optional [extra "test"] [valid-time 1800]]
  "生成二维码链接"
  (some-> (requests.post "http://wxpusher.zjiecode.com/api/fun/create/qrcode"
                         :json {"appToken" token
                                "extra" extra
                                "validTime" valid-time})
          (.json)
          (get "data" "url")))

(defn get-all-user
  [token]
  (some-> (requests.get "http://wxpusher.zjiecode.com/api/fun/wxuser"
                        :params {"appToken" token})
          (.json)
          (as-> resp
                (try (get resp "data" "records")
                     (except [e Exception]
                       (logging.error "get all user response:%s error:%s" resp e))))))

(defn get-all-uids [token]
  "获取所有用户id"
  (some->> (get-all-user token)
           (map #%(of %1 "uid"))
           list))

(defclass ContentType [Enum]
  "消息类型"
  (setv text 1)
  (setv html 2)
  (setv markdown 3))

(defn send-message
  [token message &optional [content-type "text"] [uids []]]
  "发送消息，当`uids`为空时，发送给所有用户"
  (setv now (-> (datetime.now)
                (.strftime "[%Y-%m-%d %H:%M:%S]")))
  (some-> (requests.get "http://wxpusher.zjiecode.com/api/send/message"
                        :params {"appToken" token
                                 "content" f"{now} {message}"
                                 "contentType" (-> (of ContentType content-type)
                                                   (. value))
                                 "uid" (if (empty? uids)
                                            (get-all-uids token)
                                            uids)})
          (.json)
          (->> (logging.info "send messges %s result: %s" uids))))

(defmainf [&rest args]
  (setv opts (parse-args [["--reset"
                           :action "store_true"
                           :help "重置配置文件"]
                          ["-s" "--show-qrcode"
                           :action "store_true"
                           :help "显示二维码，进行关注"]
                          ["-t" "--content-type"
                           :default "text"
                           :type str
                           :choices ["text" "html" "markdown"]
                           :nargs "?"
                           :help "发送的消息类型 (default: %(default)s)"]
                          ["-v" "--verbose"
                           :nargs "?"
                           :type int
                           :default 0
                           :help "日志输出级别(0,1,2)　 (default: %(default)s)"]
                          ["message" :nargs "?" :help "消息内容"]]
                         (rest args)
                         :description "发送微信消息"))

  (set-logging-level opts.verbose)

  (setv token (some-> (read-config)
                      (.get "token")))
  (when (or (not token)
            opts.reset)
    (unless token
      (print "未发现token配置"))

    (print "访问 http://wxpusher.zjiecode.com/admin/app/list 创建token.")
    (while True
      (setv token (-> (input "输入申请的APP_TOKEN:")
                      (.strip)))
      (when (and (not (empty? token))
                 (get-all-user token))
        (break)))

    (save-config {"token" token})

    (print "\n网页打开下面的网址，微信扫码关注以接收消息：")
    (print (make-qrcode token)))

  (when opts.show-qrcode
    (print "网页打开下面的网址，微信扫码关注以接收消息：")
    (print (make-qrcode token)))

  (when opts.message
    (send-message :token token
                  :message opts.message
                  :content-type opts.content-type))

  (logging.info "over!")
  )

