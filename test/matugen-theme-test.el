;;; matugen-theme-test.el --- Behavior and palette regressions -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(setq load-prefer-newer t)
(load (expand-file-name "../matugen-theme.el" (file-name-directory load-file-name)) nil t)

(defconst mt-test-dark
  "background = #19120c\nforeground = #efe0d5\ncursor-color = #feb877\nselection-background = #60432a\nselection-foreground = #ffe8d0\npalette = 1=#ff7269\npalette = 2=#8dfe77\npalette = 3=#ffe569\npalette = 4=#f1a157\npalette = 5=#a05b00\npalette = 6=#feb877\n")
(defconst mt-test-light
  "background = #faf8ff\nforeground = #1b1b21\ncursor-color = #454aa0\npalette = 1=#a03050\npalette = 2=#286030\npalette = 3=#785500\npalette = 4=#454aa0\npalette = 5=#743f80\npalette = 6=#006878\n")

(defmacro mt-test-with-env (&rest body)
  "Isolate runtime resources and files used by BODY."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "matugen-ert-" t))
          (matugen-theme-colors-file (expand-file-name "colors.conf" dir))
          (matugen-theme-fallback-colors-file nil)
          (matugen-theme-mode nil) (matugen-theme--generation 0)
          (matugen-theme--watches nil) (matugen-theme--timer nil)
          (matugen-theme--poll-timer nil) (matugen-theme--file-state nil)
          (matugen-theme--last-palette nil) (matugen-theme--last-key nil)
          (matugen-theme--last-error nil) (matugen-theme--watch-error nil)
          (matugen-theme--roles nil) (matugen-theme--retry-count 0)
          (matugen-theme--previewing nil)
          (matugen-theme-style 'coding) (matugen-theme-palette 'preset)
          (matugen-theme-emphasis 'preset) (matugen-theme-semantic-colors 'auto)
          (matugen-theme-heading-scale 1.0) (matugen-theme-update-delay 0.1)
          (matugen-theme-after-apply-hook nil) (matugen-theme-poll-interval 5)
          (old-themes (copy-sequence custom-enabled-themes))
          (old-background (frame-parameter nil 'background-mode))
          (inhibit-message t))
     (unwind-protect
         (progn (with-temp-file matugen-theme-colors-file (insert mt-test-dark))
                (mapc #'disable-theme (copy-sequence custom-enabled-themes))
                ,@body)
       (matugen-theme-mode -1)
       (mapc #'disable-theme (copy-sequence custom-enabled-themes))
       (mapc #'enable-theme (reverse old-themes))
       (set-frame-parameter nil 'background-mode old-background)
       (delete-directory dir t))))

(defun mt-test-spec (face specs)
  (cadar (cadr (assq face specs))))

(ert-deftest mt-parser-normalizes-whitespace-and-case ()
  (let ((p (matugen-theme--parse-palette
            " # comment\n background= #ABCDEF \nforeground\t=\t#010203 # comment\npalette= 4 = #aabbcc\nfont-size = 15\n")))
    (should (equal (alist-get 'background p) "#abcdef"))
    (should (equal (alist-get 'palette-4 p) "#aabbcc"))))

(ert-deftest mt-parser-rejects-invalid-or-incomplete-input ()
  (dolist (text '("foreground = #ffffff\n"
                  "background = #12\nforeground = #ffffff\n"
                  "background = #fffggg\nforeground = #ffffff\n"
                  "background = #1234567\nforeground = #ffffff\n"
                  "background = #123456\nforeground = #ffffff\npalette = 16=#111111\n"))
    (should-error (matugen-theme--parse-palette text) :type 'matugen-theme-invalid-palette)))

(ert-deftest mt-mid-gray-contrast-chooses-working-direction ()
  (let ((color (matugen-theme--ensure-contrast "#888888" "#888888" t 4.5)))
    (should (>= (matugen-theme--contrast-ratio color "#888888") 4.5))
    (should (< (matugen-theme--luminance color) (matugen-theme--luminance "#888888")))))

(ert-deftest mt-contrast-quantization-and-impossible-target ()
  (dotimes (i 256)
    (let* ((bg (format "#%02x%02x%02x" i i i))
           (fg (matugen-theme--ensure-contrast "#ba70ca" bg nil 4.5)))
      (should (>= (matugen-theme--contrast-ratio fg bg) 4.5))))
  (should-error (matugen-theme--ensure-contrast "#888888" "#888888" nil 21)))

(ert-deftest mt-role-contrast-across-profiles-and-inputs ()
  (mt-test-with-env
    (dolist (input (append (list mt-test-dark mt-test-light)
                          (mapcar (lambda (bg)
                                    (format "background = %s\nforeground = #ffffff\ncursor-color = %s\n" bg bg))
                                  '("#000000" "#ffffff" "#888888" "#777777" "#00ff00" "#ff00ff"))))
      (dolist (preset matugen-theme--profiles)
        (setq matugen-theme-style (car preset))
        (let ((r (matugen-theme--build-roles (matugen-theme--parse-palette input))))
          (dolist (foreground '(text text-muted accent variable string type function keyword constant error warning success))
            (dolist (background '(surface surface-raised surface-active))
              (should (>= (matugen-theme--contrast-ratio (alist-get foreground r) (alist-get background r)) 4.5))))
          (should (>= (matugen-theme--contrast-ratio (alist-get 'selection-fg r) (alist-get 'selection-bg r)) 4.5))
          (should (>= (matugen-theme--contrast-ratio (alist-get 'cursor r) (alist-get 'surface r)) 3)))))))

(ert-deftest mt-neutral-minimal-is-achromatic-and-uniform ()
  (mt-test-with-env
    (setq matugen-theme-style 'monochrome)
    (let* ((r (matugen-theme--build-roles (matugen-theme--parse-palette mt-test-dark)))
           (specs (matugen-theme-faces-build r)))
      (dolist (pair r)
        (when (and (stringp (cdr pair)) (string-prefix-p "#" (cdr pair)))
          (let ((rgb (matugen-theme--hex-to-rgb (cdr pair))))
            (should (= (nth 0 rgb) (nth 1 rgb) (nth 2 rgb))))))
      (dolist (role '(variable string type function keyword constant error warning success))
        (should (equal (alist-get role r) (alist-get 'text r))))
      (should (= 1.0 (plist-get (mt-test-spec 'org-level-1 specs) :height)))
      (should (equal (plist-get (mt-test-spec 'org-link specs) :foreground) (alist-get 'text r))))))

(ert-deftest mt-independent-policy-overrides ()
  (mt-test-with-env
    (setq matugen-theme-style 'neon matugen-theme-palette 'neutral matugen-theme-emphasis 'minimal)
    (should (equal (matugen-theme--policy) '(neutral minimal)))))

(ert-deftest mt-surfaces-remain-distinct-near-the-contrast-boundary ()
  (mt-test-with-env
    (setq matugen-theme-style 'monochrome)
    (let ((r (matugen-theme--build-roles
              (matugen-theme--parse-palette "background = #757575\nforeground = #000000\n"))))
      (should-not (equal (alist-get 'surface r) (alist-get 'surface-active r)))
      (should (>= (matugen-theme--contrast-ratio (alist-get 'text r) (alist-get 'surface-active r)) 4.5)))))

(ert-deftest mt-selection-replaces-syntax-and-respects-imported-pair ()
  (mt-test-with-env
    (let* ((r (matugen-theme--build-roles (matugen-theme--read-palette)))
           (specs (matugen-theme-faces-build r)))
      (should (equal (alist-get 'selection-bg r) "#60432a"))
      (should (equal (plist-get (mt-test-spec 'region specs) :foreground) (alist-get 'selection-fg r)))
      (should (equal (plist-get (mt-test-spec 'region specs) :background) (alist-get 'selection-bg r))))))

(ert-deftest mt-org-markdown-and-diagnostics-have-explicit-coverage ()
  (mt-test-with-env
    (let ((specs (matugen-theme-faces-build (matugen-theme--build-roles (matugen-theme--read-palette)))))
      (dolist (face '(org-link org-date org-todo org-done org-checkbox org-table org-tag
                     markdown-code-face markdown-header-face-1 markdown-link-face
                     flymake-error flycheck-warning diff-added diff-removed isearch-fail))
        (should (assq face specs))))))

(ert-deftest mt-rejected-write-preserves-theme ()
  (mt-test-with-env
    (should (matugen-theme-reload))
    (let ((key matugen-theme--last-key) (roles matugen-theme--roles)
          (settings (copy-tree (get 'matugen 'theme-settings))))
      (dolist (text '("foreground = #ffffff\n" "background = #12\nforeground = #ffffff\n"))
        (with-temp-file matugen-theme-colors-file (insert text))
        (should-not (matugen-theme-reload))
        (should (equal key matugen-theme--last-key))
        (should (equal roles matugen-theme--roles))
        (should (equal settings (get 'matugen 'theme-settings)))
        (should (custom-theme-enabled-p 'matugen))))))

(ert-deftest mt-unchanged-palette-does-not-reapply-or-run-hooks ()
  (mt-test-with-env
    (let ((calls 0))
      (add-hook 'matugen-theme-after-apply-hook (lambda () (cl-incf calls)))
      (matugen-theme-reload)
      (matugen-theme-reload)
      (should (= calls 1))
      (matugen-theme-reload t)
      (should (= calls 2)))))

(ert-deftest mt-reload-does-not-toggle-solaires-or-reload-fonts ()
  (mt-test-with-env
    (cl-letf (((symbol-function 'solaire-global-mode) (lambda (&rest _) (ert-fail "Solaire toggled")))
              ((symbol-function 'doom/reload-theme) (lambda () (ert-fail "Doom reloaded")))
              ((symbol-function 'doom/reload-font) (lambda () (ert-fail "Font reloaded"))))
      (matugen-theme-reload)
      (setq matugen-theme-style 'writing)
      (matugen-theme-reload))))

(ert-deftest mt-integration-hook-error-does-not-misreport-a-valid-palette ()
  (mt-test-with-env
    (let ((calls 0))
      (setq matugen-theme-after-apply-hook
            (list (lambda () (error "Optional integration failed"))
                  (lambda () (cl-incf calls))))
      (should (matugen-theme-reload))
      (should (custom-theme-enabled-p 'matugen))
      (should-not matugen-theme--last-error)
      (should (= calls 1)))))

(ert-deftest mt-atomic-rename-destination-schedules-refresh ()
  (mt-test-with-env
    (let ((matugen-theme-mode t) (calls 0))
      (cl-letf (((symbol-function 'matugen-theme--schedule) (lambda (&rest _) (cl-incf calls))))
        (matugen-theme--watcher-callback (list 'desc 'renamed (expand-file-name "temp" dir) matugen-theme-colors-file))
        (should (= calls 1))
        (matugen-theme--watcher-callback (list 'desc 'changed (expand-file-name "unrelated" dir)))
        (should (= calls 1))))))

(ert-deftest mt-repeated-enable-and-disable-release-all-resources ()
  (mt-test-with-env
    (matugen-theme-mode 1)
    (let ((old (mapcar #'cdr matugen-theme--watches))
          (old-timer matugen-theme--timer) (old-poll matugen-theme--poll-timer)
          (remove-watch (symbol-function 'file-notify-rm-watch)) removed)
      ;; Some backends immediately reuse descriptor IDs.  Check the removal
      ;; calls and final watch count instead of treating reused IDs as leaks.
      (cl-letf (((symbol-function 'file-notify-rm-watch)
                 (lambda (watch) (push watch removed) (funcall remove-watch watch))))
        (matugen-theme-mode 1))
      (dolist (watch old) (should (member watch removed)))
      (should (= (length old) (length matugen-theme--watches)))
      (should-not (memq old-timer timer-list))
      (should-not (memq old-poll timer-list))
      (let ((new (mapcar #'cdr matugen-theme--watches)))
        (should new)
        (matugen-theme-mode -1)
        (dolist (watch new) (should-not (file-notify-valid-p watch)))
        (should-not matugen-theme--timer)
        (should-not matugen-theme--poll-timer)
        (should-not (memq #'matugen-theme--startup emacs-startup-hook))
        (should-not (memq #'matugen-theme--sync-frame after-make-frame-functions))))))

(ert-deftest mt-late-timer-cannot-revive-a-disabled-or-restarted-mode ()
  (mt-test-with-env
    (matugen-theme-mode 1)
    (let ((generation matugen-theme--generation) (calls 0))
      (matugen-theme-mode -1)
      (cl-letf (((symbol-function 'matugen-theme-reload) (lambda (&rest _) (cl-incf calls))))
        (matugen-theme--refresh generation)
        (should (= calls 0))
        (matugen-theme-mode 1)
        (matugen-theme--refresh generation)
        (should (= calls 0))))))

(ert-deftest mt-event-burst-has-one-pending-timer ()
  (mt-test-with-env
    (matugen-theme-mode 1)
    (let (previous)
      (dotimes (_ 20)
        (setq previous matugen-theme--timer)
        (matugen-theme--watcher-callback (list 'desc 'changed matugen-theme-colors-file))
        (should-not (memq previous timer-list)))
      (should (memq matugen-theme--timer timer-list)))))

(ert-deftest mt-primary-appearance-and-deletion-switch-source ()
  (mt-test-with-env
    (setq matugen-theme-fallback-colors-file matugen-theme-colors-file
          matugen-theme-colors-file (expand-file-name "new/colors.conf" dir))
    (matugen-theme-mode 1)
    (matugen-theme--refresh matugen-theme--generation)
    (should (equal (alist-get 'surface matugen-theme--roles) "#19120c"))
    (make-directory (file-name-directory matugen-theme-colors-file))
    (with-temp-file matugen-theme-colors-file (insert mt-test-light))
    (matugen-theme--poll)
    (should (= 2 (length matugen-theme--watches)))
    (matugen-theme--refresh matugen-theme--generation)
    (should (equal (alist-get 'surface matugen-theme--roles) "#faf8ff"))
    (delete-file matugen-theme-colors-file)
    (matugen-theme--refresh matugen-theme--generation)
    (should (equal (alist-get 'surface matugen-theme--roles) "#19120c"))))

(ert-deftest mt-stopped-observer-is-recovered ()
  (mt-test-with-env
    (matugen-theme-mode 1)
    (file-notify-rm-watch (cdar matugen-theme--watches))
    (matugen-theme--poll)
    (should (file-notify-valid-p (cdar matugen-theme--watches)))))

(ert-deftest mt-notifications-unavailable-use-polling ()
  (mt-test-with-env
    (cl-letf (((symbol-function 'file-notify-add-watch)
               (lambda (&rest _) (signal 'file-notify-error '("unsupported")))))
      (matugen-theme-mode 1)
      (should matugen-theme--poll-timer)
      (matugen-theme--refresh matugen-theme--generation)
      (should (custom-theme-enabled-p 'matugen)))))

(ert-deftest mt-invalid-write-has-bounded-retries ()
  (mt-test-with-env
    (matugen-theme-mode 1)
    (with-temp-file matugen-theme-colors-file (insert "background = #12"))
    (let ((scheduled 0))
      (cl-letf (((symbol-function 'matugen-theme--schedule) (lambda (&rest _) (cl-incf scheduled))))
        (dotimes (_ 5) (matugen-theme--refresh matugen-theme--generation))
        (should (= 2 scheduled))))))

(ert-deftest mt-preview-cancel-restores-style-themes-and-frame ()
  (mt-test-with-env
    (deftheme mt-test-other)
    (custom-theme-set-faces 'mt-test-other '(default ((t (:background "#ffffff" :foreground "#000000")))))
    (enable-theme 'mt-test-other)
    (let ((old-require (symbol-function 'require))
          (doom-theme 'mt-test-other)
          (matugen-theme-mode t) (scheduled 0)
          (before (frame-parameter nil 'background-mode)))
      (cl-letf (((symbol-function 'require)
                 (lambda (feature &rest args) (if (eq feature 'consult) t (apply old-require feature args))))
                ((symbol-function 'matugen-theme--schedule)
                 (lambda (&rest _) (cl-incf scheduled)))
                ((symbol-function 'consult--read)
                 (lambda (_choices &rest args)
                   (let ((state (plist-get args :state)))
                     (funcall state 'preview "neon")
                     (should (eq matugen-theme-style 'neon))
                     (funcall state 'preview nil)
                     (should (eq matugen-theme-style 'coding))
                     (funcall state 'exit nil)
                     (funcall state 'return nil)
                     (signal 'quit nil)))))
        (condition-case nil (matugen-theme-select-style) (quit nil)))
      (should (eq matugen-theme-style 'coding))
      (should (equal custom-enabled-themes '(mt-test-other)))
      (should (eq doom-theme 'mt-test-other))
      (should (= scheduled 0))
      (should (eq before (frame-parameter nil 'background-mode))))))

(ert-deftest mt-preview-error-restores-original-profile ()
  (mt-test-with-env
    (matugen-theme-reload)
    (let ((old-require (symbol-function 'require)))
      (cl-letf (((symbol-function 'require)
                 (lambda (feature &rest args) (if (eq feature 'consult) t (apply old-require feature args))))
                ((symbol-function 'consult--read)
                 (lambda (_choices &rest args)
                   (funcall (plist-get args :state) 'preview "writing")
                   (error "Preview interrupted"))))
        (should-error (matugen-theme-select-style)))
      (should (eq matugen-theme-style 'coding))
      (should (custom-theme-enabled-p 'matugen)))))

(ert-deftest mt-preview-confirm-uses-cached-palette ()
  (mt-test-with-env
    (matugen-theme-reload)
    (let ((old-require (symbol-function 'require)))
      (cl-letf (((symbol-function 'require)
                 (lambda (feature &rest args) (if (eq feature 'consult) t (apply old-require feature args))))
                ((symbol-function 'matugen-theme--read-palette) (lambda () (ert-fail "Preview reread disk")))
                ((symbol-function 'consult--read)
                 (lambda (_choices &rest args)
                   (funcall (plist-get args :state) 'preview "writing")
                   (funcall (plist-get args :state) 'preview nil)
                   "writing")))
        (matugen-theme-select-style))
      (should (eq matugen-theme-style 'writing)))))

(ert-deftest mt-startup-registers-and-removes-a-named-hook ()
  (mt-test-with-env
    (let ((after-init-time nil))
      (matugen-theme-mode 1)
      (should (memq #'matugen-theme--startup emacs-startup-hook))
      (matugen-theme-mode -1)
      (should-not (memq #'matugen-theme--startup emacs-startup-hook)))))

(ert-deftest mt-new-frames-follow-active-theme ()
  (mt-test-with-env
    (matugen-theme-reload)
    (let ((called nil))
      (cl-letf (((symbol-function 'frame-live-p) (lambda (_) t))
                ((symbol-function 'set-frame-parameter) (lambda (f key value) (push (list f key value) called)))
                ((symbol-function 'frame-set-background-mode) #'ignore))
        (matugen-theme--sync-frame 'new-frame))
      (should (equal called '((new-frame background-mode dark)))))))

;;; matugen-theme-test.el ends here
