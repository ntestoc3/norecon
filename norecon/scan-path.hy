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

(defmain [&rest args]
  (logging.basicConfig :level logging.INFO
                       ;; :filename "app.log"
                       ;; :filemode "w"
                       :style "{"
                       :format "{asctime} [{levelname}] {filename}({funcName})[{lineno}] {message}")

  (setv opts (parse-args [["-if" "--subdomains" :type str
                           :required True
                           :help "subdomains info file (subds output file)"]
                          ["-pf" "--path-file" :type str
                           :required True
                           :help "path file to scan"]
                          ["-of" "--output" :type str
                           :default "scaned-path.txt"
                           :help "scan result output file path, default `scaned-path.txt`"]
                          ]
                         (rest args)
                         :description "find subdomains for root domain"))

  (setv tmp-domain-file (os.path.join (tempfile.mkdtemp)
                                      "domains.txt"))
  (save-domains opts.subdomains tmp-domain-file)
  (ffuf opts.path-file tmp-domain-file opts.output)

  (logging.info "over!")
  )
