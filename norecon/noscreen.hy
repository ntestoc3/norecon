#!/usr/bin/env hy

(require [hy.extra.anaphoric [*]]
         [helpers [*]]
         )

(import os
        logging
        sys
        argparse
        subprocess

        [helpers [*]]
        )

(defn aquatone
  [hosts &optional
   [threads 2]
   [out-path "./"]
   [ports None]
   [scan-timeout 10]
   [http-timeout 20]
   [screenshot-timeout 60]
   [timeout 120]
   [opts []]]
  "`opts` 传递给aquatone的额外参数"
  (logging.info "aquatone hosts %s ports:%s" hosts ports)
  (try (subprocess.run ["aquatone"
                        "-silent"
                        "-out" out-path
                        "-http-timeout" (str (* 1000 http-timeout))
                        "-threads" (str threads)
                        #* (if ports
                               ["-ports" ports]
                               [])
                        "-scan-timeout" (str (* 1000 scan-timeout))
                        "-screenshot-timeout" (str (* 1000 screenshot-timeout))
                        #* opts]
                       :input hosts
                       :encoding "utf-8"
                       :timeout timeout)
       (except [subprocess.TimeoutExpired]
         (logging.warn "aquatone screenshot %s timeout." hosts))))

(defn ports-arg
  [p]
  (or (in p ["small" "medium" "large" "xlarge"])
      (for [p1 (.split p ",")]
        (if (< 0 (int p1) 65536)
            True
            (raise (argparse.ArgumentTypeError f"{p} not valid ports")))))
  p)

(defmainf [&rest args]
  (setv opts (parse-args [["-o" "--output-dir"
                           :type str
                           :default "./"
                           :help "输出文件夹"]
                          ["-hs" "--hosts"
                           :nargs "?"
                           :type (argparse.FileType "r")
                           :default sys.stdin
                           :help "包含主机列表的文件"]
                          ["-st" "--scan-timeout"
                           :type int
                           :default 20
                           :help "扫描端口超时时间(秒) (default: %(default)s)"
                           ]
                          ["-ht" "--http-timeout"
                           :type int
                           :default 30
                           :help "http请求超时时间(秒) (default: %(default)s)"
                           ]
                          ["-sst" "--screenshot-timeout"
                           :type int
                           :default 180
                           :help "屏幕快照超时时间(秒) (default: %(default)s)"
                           ]
                          ["-t" "--timeout"
                           :type int
                           :default 1800
                           :help "程序运行超时时间(秒) (default: %(default)s)"
                           ]
                          ["--threads"
                           :type int
                           :default 5
                           :help "同时进行快照的进程 (default: %(default)s)"]
                          ["-p" "--ports"
                           :type ports-arg
                           :default "medium"
                           :help "扫描检测的端口 (default: %(default)s)"
                           ]
                          ["-v" "--verbose"
                           :nargs "?"
                           :type int
                           :default 0
                           :help "日志输出级别(0,1,2)　 (default: %(default)s)"]
                          ["host" :nargs "*" :help "要检测的主机"]
                          ]
                         (rest args)
                         :description "进行屏幕快照并输出"))

  (set-logging-level opts.verbose)

  (setv hosts (->> (read-nargs-or-input-file opts.host opts.hosts)
                   (str.join " ")))

  (aquatone hosts
            :threads opts.threads
            :out-path opts.output-dir
            :ports opts.ports
            :scan-timeout opts.scan-timeout
            :http-timeout opts.http-timeout
            :screenshot-timeout  opts.screenshot-timeout
            :timeout opts.timeout
            )

  (logging.info "over!")
  )
