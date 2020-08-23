#!/usr/bin/env hy

(require [hy.extra.anaphoric [*]]
         [helpers [*]]
         )

(import os
        logging
        sys
        argparse
        time
        csv
        io
        requests

        [ipaddress [ip-address]]
        [retry [retry]]
        [helpers [*]]
        )

(defn ipv4?
  [ip]
  (-> (ip-address ip)
      (. version)
      (= 4)))

(with-decorator (retry Exception :delay 5 :backoff 4 :max-delay 120)
  (defn get-nameservers
    [&optional [ipv6 False] [min-reliability 1]]
    (setv valid-ip? (comp (if ipv6
                              not
                              identity)
                          ipv4?))
    (some-> (requests.get "https://public-dns.info/nameservers.csv")
            (. text)
            (io.StringIO)
            csv.DictReader
            (->> (filter #%(and (valid-ip? (of %1 "ip_address"))
                                (>= (float (of %1 "reliability"))
                                    min-reliability))))
            (sorted :key #%(of %1 "reliability"))
            (->> (map #%(of %1 "ip_address")))
            list)))

(defn float-range [x &optional [min-f 0.1] [max-f 1.0]]
  (try
    (setv r (float x))
    (except [e ValueError]
      (raise (argparse.ArgumentTypeError f"{x} not a floating point value."))))
  (when (or (< r min-f)
            (> r max-f))
    (raise (argparse.ArgumentTypeError f"{x} not in range [{min-f :.2f} {max-f :.2f}]."))
    )
  r)

(defmain [&rest args]
  (logging.basicConfig :level logging.INFO
                       :style "{"
                       :format "{asctime} [{levelname}] {filename}({funcName})[{lineno}] {message}")

  (setv opts (parse-args [["-6" "--ipv6"
                           :action "store_true"
                           :help "use ipv6 dns server"]
                          ["-r" "--reliability"
                           :type float-range
                           :default 1
                           :help "min dns server reliability"]
                          ["-o" "--output"
                           :nargs "?"
                           :type (argparse.FileType "w")
                           :default sys.stdout
                           :help "output domain resolver ip to file"]
                          ]
                         (rest args)
                         :description "valid domain resolve"))
  (->> (get-nameservers :ipv6 opts.ipv6
                        :min-reliability opts.reliability)
       (.join "\n")
       (opts.output.write))
  )
