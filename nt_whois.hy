#!/usr/bin/env hy

(require [hy.extra.anaphoric [*]]
         [helpers [*]]
         )

(import json
        re
        os
        logging
        sys
        argparse
        csv
        validators
        whois

        [retry [retry]]
        [helpers [*]]
        [ipwhois [IPWhois]]
        [publicsuffix2 [get-public-suffix]]
        )

(with-decorator (retry Exception :delay 100 :backoff 4 :max-delay 280)
 (defn nt-whois
   [target]
   (cond [(or (validators.ipv4 target)
              (validators.ipv6 target))
          (-> (IPWhois target)
              (.lookup-rdap :asn-methods ["dns" "whois" "http"]))]

         [(validators.domain target)
          (-> (get-public-suffix target)
              (whois.whois))]

         [True
          (logging.warn "not a valid domain or ip: %s" target)])))

(defmain [&rest args]
  (logging.basicConfig :level logging.INFO
                       :handlers [(logging.FileHandler :filename "nt_whois_app.log")
                                  (logging.StreamHandler sys.stderr)]
                       :style "{"
                       :format "{asctime} [{levelname}] {filename}({funcName})[{lineno}] {message}")

  (setv opts (parse-args [["-o" "--output"
                           :nargs "?"
                           :type (argparse.FileType "w")
                           :default sys.stdout
                           :help "输出文件名"]
                          ["target" :help "whois要查询的域名或ip"]
                          ]
                         (rest args)
                         :description "whois查询域名或ip,然后输出json"))

  (-> (nt-whois opts.target)
      (json.dump opts.output :indent 2 :sort-keys True :default str))

  (logging.info "over!")
  )
