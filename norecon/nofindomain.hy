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
        tempfile

        [helpers [*]]
        )

(defn findomain
  [domain &optional [timeout 30] [opts []]]
  (try (setv out-file (tempfile.mktemp :prefix "fd_" :suffix "txt"))
       (logging.info "findomain scan %s temp save to %s." domain out-file)
       (setv r (subprocess.run ["findomain"
                                #* opts
                                "-u" out-file
                                "-t" domain]
                               :timeout (* 60 (inc timeout))
                               :encoding "utf-8"
                               :stdout subprocess.PIPE))
       (if (zero? r.returncode)
           (do (with [f (open out-file)]
                 (setv r (read-valid-lines f)))
               (os.unlink out-file)
               r)
           (logging.warning "findomain %s error: %s" domain r.stderr))
       (except [subprocess.TimeoutExpired]
         (logging.warn "findomain %s timeout." domain))))

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
                           :const 1
                           :help "日志输出级别(0,1,2)  (default: %(default)s)"]
                          ["target" :help "目标"]]
                         (rest args)
                         :description "使用findomain查询子域名"))

  (set-logging-level opts.verbose)

  (some->> (findomain opts.target :timeout opts.timeout)
           (str.join "\n")
           (opts.output.write))

  (logging.info "over!")
  )
