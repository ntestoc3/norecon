#!/usr/bin/env hy

(require [hy.extra.anaphoric [*]]
         [helpers [*]]
         )

(import os
        logging
        sys
        re
        argparse
        subprocess

        [helpers [*]]
        )

(defn parse-out
  [s]
  (->> s
       (re.findall r"\[(\w+?)\]\s+(.+?)\s")
       (map second)
       list))

(defn amass
  [domain &optional [timeout 30] [out-file None] [opts []]]
  (logging.info "amass scan %s in %s minutes." domain timeout)
  (try (setv r (subprocess.run ["amass"
                                "enum"
                                "-src"
                                #* (if out-file
                                       ["-json" out-file]
                                       [])
                                "-timeout" (str timeout)
                                #* opts
                                "-d" domain]
                               :timeout (* 60 (inc timeout))
                               :encoding "utf-8"
                               :stdout subprocess.PIPE))
       (if (zero? r.returncode)
           (parse-out r.stdout)
           (logging.warning "amass enum domain %s error: %s" domain r.stderr))
       (except [subprocess.TimeoutExpired]
         (logging.warn "amass enum domain %s timeout." domain))))


(defmainf [&rest args]
  (setv opts (parse-args [["-o" "--output"
                           :nargs "?"
                           :type (argparse.FileType "w")
                           :default sys.stdout
                           :help "输出文件名"]
                          ["-t" "--timeout"
                           :type int
                           :default 30
                           :help "查询执行时间(分钟) (default: %(default)s)"]
                          ["-v" "--verbose"
                           :nargs "?"
                           :type int
                           :default 0
                           :help "日志输出级别(0,1,2)　 (default: %(default)s)"]
                          ["target" :help "目标"]]
                         (rest args)
                         :description "使用amass查询子域名"))

  (set-logging-level opts.verbose)

  (->> (amass opts.target :timeout opts.timeout)
       (str.join "\n")
       (opts.output.write))

  (logging.info "over!")
  )
