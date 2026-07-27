;;; test/test-helper.el --- Helper script for batch testing

(require 'package)
(setq package-user-dir (expand-file-name ".test-elpa" (locate-dominating-file default-directory "Makefile")))
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)
(unless package-archive-contents
  (package-refresh-contents))
(defvar orgmine-test-dependencies '(request s elmine))
(dolist (pkg orgmine-test-dependencies)
  (unless (package-installed-p pkg)
    (package-install pkg)))
(provide 'test-helper)
