#!/usr/bin/env hy

(require [hy.extra.anaphoric [*]]
         [helpers [*]]
         )

(import csv
        subprocess
        logging
        os
        tempfile
        )


(defn ffuf
  [path-file domain-file out-file]
  (subprocess.run ["ffuf" "-w" f"{path-file}:PARA"
                   "-w" f"{domain-file}:URL"
                   "-u" "https://URL/PARA"
                   "-c"
                   "-o" out-file
                   "-of" "csv"
                   "-mc" "200,204,500"
                   ] ))

(defn save-domains
  [domain-info-file out-file]
  (with [f (open domain-info-file)
         w (open out-file "w")]
    (for [row (csv.reader f :delimiter ",")]
      (->> (first row)
           (.write w))
      (.write w "\n"))))

(defmainf [&rest args]
  (setv opts (parse-args [["-if" "--subdomains" :type str
                           :required True
                           :help "主机文件"]
                          ["-pf" "--path-file" :type str
                           :required True
                           :help "参数文件"]
                          ["-of" "--output" :type str
                           :default "scaned-path.txt"
                           :help "输出查询结果　 (default: %(default)s)"]
                          ["-v" "--verbose"
                           :nargs "?"
                           :type int
                           :default 0
                           :help "日志输出级别(0,1,2)　 (default: %(default)s)"]]
                         (rest args)
                         :description "查询所有(https://主机/参数)的合法请求"))

  (set-logging-level opts.verbose)

  (setv tmp-domain-file (os.path.join (tempfile.mkdtemp)
                                      "domains.txt"))
  (save-domains opts.subdomains tmp-domain-file)
  (ffuf opts.path-file tmp-domain-file opts.output)

  (logging.info "over!")
  )
