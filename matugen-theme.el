;;; matugen-theme.el --- Semantic themes from Matugen palettes -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Diego
;; Author: Diego
;; Version: 1.1.0
;; Package-Requires: ((emacs "28.1"))
;; Keywords: faces, themes

;;; Commentary:
;; Read a Ghostty-style palette, validate it, build semantic color roles and
;; apply an Emacs theme.  Palette policy and visual emphasis are independent.
;; Failed or incomplete writes leave the last valid theme untouched.
;; See README.md for profiles, customization and the local test command.

;;; Code:
(require 'cl-lib)
(require 'color)
(require 'filenotify)
(require 'subr-x)
(require 'matugen-theme-faces
         (expand-file-name "matugen-theme-faces"
                           (file-name-directory
                            (or load-file-name (bound-and-true-p byte-compile-current-file)
                                buffer-file-name))))

(defgroup matugen-theme nil
  "A dynamic theme with explicit palette and emphasis policies."
  :group 'faces :prefix "matugen-theme-")

(defconst matugen-theme--profiles
  '((coding system balanced "System colors with semantic syntax highlighting")
    (writing tinted minimal "Quiet, lightly tinted text for Org and Markdown")
    (monochrome neutral minimal "Neutral surfaces and one content color")
    (presentation system vivid "Stronger emphasis with modestly larger headings")
    (full system balanced "Compatibility name for coding")
    (accent neutral balanced "Neutral content with a system UI accent")
    (background system minimal "System background with one content color")
    (harmonized tinted balanced "Reduced chroma with balanced emphasis")
    (neon system vivid "More saturated syntax, with validated contrast"))
  "Presets: (NAME PALETTE EMPHASIS DESCRIPTION).")

(defcustom matugen-theme-style 'coding
  "Preset used by the theme.  Palette and emphasis overrides take precedence."
  :type (cons 'choice
              (mapcar (lambda (p) (list 'const :tag (nth 3 p) (car p)))
                      matugen-theme--profiles)))
(defcustom matugen-theme-palette 'preset
  "Color policy: original system colors, low-chroma tints or neutral grays."
  :type '(choice (const preset) (const system) (const tinted) (const neutral)))
(defcustom matugen-theme-emphasis 'preset
  "Visual emphasis, independent of the palette policy."
  :type '(choice (const preset) (const minimal) (const balanced) (const vivid)))
(defcustom matugen-theme-semantic-colors 'auto
  "Whether error, warning and success use color.
With `auto', minimal profiles use weight and underlining instead of color."
  :type '(choice (const auto) (const :tag "Always" t) (const :tag "Never" nil)))
(defcustom matugen-theme-heading-scale 1.0
  "Multiplier for heading sizes; body text and fonts remain user-controlled."
  :type 'number)
(defcustom matugen-theme-colors-file
  (expand-file-name "~/.config/emacs/matugen-colors.conf")
  "Primary palette file.  Both background and foreground are required."
  :type 'file)
(defcustom matugen-theme-fallback-colors-file
  (expand-file-name "~/.config/ghostty/themes/dankcolors")
  "Fallback palette used only when the primary file is absent; nil disables it."
  :type '(choice file (const nil)))
(defcustom matugen-theme-update-delay 0.15
  "Seconds to group filesystem events before a refresh."
  :type 'number)
(defcustom matugen-theme-poll-interval 5
  "Seconds between recovery checks for missing files or stopped observers.
These checks compare file attributes before reading or recalculating colors."
  :type 'number)
(defcustom matugen-theme-after-apply-hook nil
  "Hook run once after successfully applying changed colors or options."
  :type 'hook)

(define-error 'matugen-theme-invalid-palette "Invalid Matugen palette")
(defvar matugen-theme-mode nil)
(defvar matugen-theme--last-palette nil)
(defvar matugen-theme--last-key nil)
(defvar matugen-theme--roles nil)
(defvar matugen-theme--watches nil)
(defvar matugen-theme--timer nil)
(defvar matugen-theme--poll-timer nil)
(defvar matugen-theme--file-state nil)
(defvar matugen-theme--retry-count 0)
(defvar matugen-theme--last-error nil)
(defvar matugen-theme--watch-error nil)
(defvar matugen-theme--previewing nil)
(defvar matugen-theme--generation 0)
(defvar doom-theme)
(declare-function consult--read "consult")

;;; Input: strict values, flexible whitespace, no changes to the active theme.

(defun matugen-theme--get-file-path ()
  "Resolve the primary path or, if absent, the explicit fallback."
  (let ((primary (expand-file-name matugen-theme-colors-file)))
    (if (or (file-exists-p primary) (not matugen-theme-fallback-colors-file))
        primary
      (expand-file-name matugen-theme-fallback-colors-file))))

(defun matugen-theme--parse-palette (text)
  "Parse TEXT to a normalized alist or signal `matugen-theme-invalid-palette'.
Ignore unrelated terminal settings.  Recognized colors must be #RRGGBB;
palette indices must be in 0..15.  Duplicate keys use the last value."
  (let (result)
    (dolist (line (split-string text "\n"))
      (when (string-match "\\`[ \t]*\\([a-z-]+\\)[ \t]*=[ \t]*\\(.*\\)\\'" line)
        (let ((name (match-string 1 line)) (value (string-trim (match-string 2 line))))
          (when (or (equal name "palette")
                    (member name '("background" "foreground" "cursor-color" "accent"
                                   "selection-background" "selection-foreground"
                                   "error" "warning" "success")))
            (when (equal name "palette")
              (unless (and (string-match "\\`\\([0-9]+\\)[ \t]*=[ \t]*\\(.*\\)\\'" value)
                           (<= (string-to-number (match-string 1 value)) 15))
                (signal 'matugen-theme-invalid-palette (list "Invalid palette index" line)))
              (setq name (format "palette-%d" (string-to-number (match-string 1 value)))
                    value (match-string 2 value)))
            (unless (string-match "\\`\\(#[[:xdigit:]]\\{6\\}\\)\\(?:[ \t]+#.*\\)?[ \t]*\\'" value)
              (signal 'matugen-theme-invalid-palette (list "Expected #RRGGBB" name value)))
            (setf (alist-get (intern name) result) (downcase (match-string 1 value)))))))
    (dolist (key '(background foreground))
      (unless (alist-get key result)
        (signal 'matugen-theme-invalid-palette (list "Missing required color" key))))
    (sort result (lambda (a b) (string< (symbol-name (car a)) (symbol-name (car b)))))))

(defun matugen-theme--read-palette ()
  "Read and validate the currently resolved palette file."
  (with-temp-buffer
    (insert-file-contents (matugen-theme--get-file-path))
    (matugen-theme--parse-palette (buffer-string))))

;;; Color math.  Contrast is checked after rounding to the rendered hex color.

(defun matugen-theme--hex-to-rgb (hex)
  "Convert a validated HEX string to normalized sRGB components."
  (mapcar (lambda (i) (/ (string-to-number (substring hex i (+ i 2)) 16) 255.0))
          '(1 3 5)))

(defun matugen-theme--rgb-to-hex (rgb)
  "Convert normalized RGB to a clamped, rounded hex color."
  (apply #'format "#%02x%02x%02x"
         (mapcar (lambda (v) (max 0 (min 255 (round (* v 255))))) rgb)))

(defun matugen-theme--relative-luminance (r g b)
  "Return the relative luminance of normalized sRGB R, G and B."
  (cl-loop for v in (list r g b) for weight in '(0.2126 0.7152 0.0722)
           sum (* weight (if (<= v 0.04045) (/ v 12.92)
                           (expt (/ (+ v 0.055) 1.055) 2.4)))))

(defun matugen-theme--luminance (hex)
  "Return the relative luminance of HEX."
  (apply #'matugen-theme--relative-luminance (matugen-theme--hex-to-rgb hex)))

(defun matugen-theme--contrast-ratio (a b)
  "Return the contrast ratio between hex colors A and B."
  (let ((x (matugen-theme--luminance a)) (y (matugen-theme--luminance b)))
    (/ (+ (max x y) 0.05) (+ (min x y) 0.05))))

(defun matugen-theme--is-dark-color (hex)
  "Return non-nil when white has more contrast against HEX than black."
  (> (matugen-theme--contrast-ratio hex "#ffffff")
     (matugen-theme--contrast-ratio hex "#000000")))

(defun matugen-theme--blend (a b alpha)
  "Mix ALPHA of sRGB color A with the remaining fraction of B.
This is an explicit sRGB mix, not a perceptually uniform interpolation."
  (matugen-theme--rgb-to-hex
   (cl-mapcar (lambda (x y) (+ (* alpha x) (* (- 1 alpha) y)))
              (matugen-theme--hex-to-rgb a) (matugen-theme--hex-to-rgb b))))

(defun matugen-theme--neutral (hex)
  "Return a gray with the same relative luminance as HEX, up to rounding."
  (let* ((l (matugen-theme--luminance hex))
         (v (if (<= l 0.0031308) (* 12.92 l)
              (- (* 1.055 (expt l (/ 1.0 2.4))) 0.055))))
    (matugen-theme--rgb-to-hex (list v v v))))

(defun matugen-theme--ensure-contrast (hex backgrounds _dark ratio)
  "Find a nearby color meeting RATIO against all BACKGROUNDS.
BACKGROUNDS is one hex color or a list.  The legacy _DARK argument is ignored:
both directions are searched.  Signal an error if no common endpoint works."
  (let* ((lums (mapcar #'matugen-theme--luminance
                       (if (stringp backgrounds) (list backgrounds) backgrounds)))
         (valid (lambda (color)
                  (let ((l (matugen-theme--luminance color)))
                    (cl-every (lambda (bg) (>= (/ (+ (max l bg) 0.05)
                                                  (+ (min l bg) 0.05)) ratio)) lums)))))
    (if (funcall valid hex) hex
      (let (candidates)
        (dolist (endpoint '("#000000" "#ffffff"))
          (when (funcall valid endpoint)
            (let ((lo 0.0) (hi 1.0) (best endpoint))
              (dotimes (_ 18)
                (let* ((amount (/ (+ lo hi) 2))
                       (candidate (matugen-theme--blend endpoint hex amount)))
                  (if (funcall valid candidate)
                      (setq hi amount best candidate)
                    (setq lo amount))))
              (push best candidates))))
        (unless candidates
          (error "No color reaches %.2f:1 against %S" ratio backgrounds))
        (let ((original (matugen-theme--hex-to-rgb hex)))
          (car (sort candidates
                     (lambda (a b)
                       (cl-flet ((distance (color)
                                   (cl-loop for x in (matugen-theme--hex-to-rgb color)
                                            for y in original sum (expt (- x y) 2))))
                         (< (distance a) (distance b)))))))))))

;;; Roles: the only place that decides what each input color means.

(defun matugen-theme--policy ()
  "Return the effective (PALETTE EMPHASIS) pair, rejecting unknown settings."
  (let* ((preset (or (assq matugen-theme-style matugen-theme--profiles)
                     (error "Unknown Matugen style: %S" matugen-theme-style)))
         (palette (if (eq matugen-theme-palette 'preset) (nth 1 preset) matugen-theme-palette))
         (emphasis (if (eq matugen-theme-emphasis 'preset) (nth 2 preset) matugen-theme-emphasis)))
    (unless (and (memq palette '(system tinted neutral))
                 (memq emphasis '(minimal balanced vivid))
                 (numberp matugen-theme-heading-scale) (> matugen-theme-heading-scale 0))
      (error "Invalid Matugen palette, emphasis or heading scale"))
    (list palette emphasis)))

(defun matugen-theme--build-roles (palette)
  "Build validated semantic roles from normalized PALETTE, without side effects."
  (pcase-let* ((`(,policy ,emphasis) (matugen-theme--policy))
               (minimal (eq emphasis 'minimal))
               (seed (or (alist-get 'accent palette) (alist-get 'cursor-color palette)
                         (alist-get 'palette-4 palette) (alist-get 'foreground palette)))
               (raw-bg (alist-get 'background palette))
               (raw-fg (alist-get 'foreground palette))
               (bg (pcase policy
                     ('neutral (matugen-theme--neutral raw-bg))
                     ('tinted (matugen-theme--blend seed (matugen-theme--neutral raw-bg) 0.035))
                     (_ raw-bg)))
               (fg-seed (pcase policy
                          ('neutral (matugen-theme--neutral raw-fg))
                          ('tinted (matugen-theme--blend seed (matugen-theme--neutral raw-fg) 0.08))
                          (_ raw-fg)))
               (fg-base (matugen-theme--ensure-contrast fg-seed bg nil 4.5))
               (pole (if (> (matugen-theme--luminance fg-base) (matugen-theme--luminance bg))
                         "#ffffff" "#000000"))
               (surface (matugen-theme--blend fg-base bg 0.035))
               (active (matugen-theme--blend fg-base bg 0.07)))
    ;; Raised surfaces must remain on the same side of a usable text endpoint.
    (let ((background-pole (if (equal pole "#ffffff") "#000000" "#ffffff")))
      (unless (>= (matugen-theme--contrast-ratio pole surface) 4.5)
        (setq surface (matugen-theme--blend background-pole bg 0.035)))
      (unless (>= (matugen-theme--contrast-ratio pole active) 4.5)
        (setq active (matugen-theme--blend background-pole bg 0.07))))
    (let* ((backgrounds (list bg surface active))
           (fg (matugen-theme--ensure-contrast fg-seed backgrounds nil 4.5))
           (muted (matugen-theme--ensure-contrast
                   (matugen-theme--blend fg bg 0.68) backgrounds nil 4.5))
           (accent-input (if (and (eq policy 'neutral) (not (eq matugen-theme-style 'accent)))
                             fg seed))
           (accent (matugen-theme--ensure-contrast accent-input backgrounds nil 4.5))
           (selection-bg (if (or minimal (eq policy 'neutral)) active
                           (or (alist-get 'selection-background palette) active)))
           (selection-fg (matugen-theme--ensure-contrast
                          (if (or minimal (eq policy 'neutral)) fg
                            (or (alist-get 'selection-foreground palette) fg))
                          selection-bg nil 4.5))
           (semantics (if (eq matugen-theme-semantic-colors 'auto)
                          (not minimal) matugen-theme-semantic-colors))
           (roles `((surface . ,bg) (surface-raised . ,surface) (surface-active . ,active)
                    (text . ,fg) (text-muted . ,muted) (accent . ,accent)
                    (selection-bg . ,selection-bg) (selection-fg . ,selection-fg)
                    (cursor . ,(matugen-theme--ensure-contrast accent-input backgrounds nil 3))
                    (emphasis . ,emphasis) (heading-scale . ,matugen-theme-heading-scale))))
      (dolist (mapping '((variable . 1) (string . 2) (type . 3)
                         (function . 4) (keyword . 5) (constant . 6)))
        (let* ((input (or (alist-get (intern (format "palette-%d" (cdr mapping))) palette) seed))
               (filtered
                (cond ((or minimal (eq policy 'neutral)) fg)
                      ((eq policy 'tinted)
                       (matugen-theme--blend seed (matugen-theme--neutral input) 0.18))
                      ((eq emphasis 'vivid)
                       (pcase-let ((`(,h ,s ,l) (apply #'color-rgb-to-hsl
                                                     (matugen-theme--hex-to-rgb input))))
                         (matugen-theme--rgb-to-hex (color-hsl-to-rgb h (min 1.0 (* 1.25 s)) l))))
                      (t input))))
          (push (cons (car mapping)
                      (matugen-theme--ensure-contrast filtered backgrounds nil 4.5)) roles)))
      (dolist (mapping '((error . "#c33c54") (warning . "#a56800") (success . "#26733a")))
        (push (cons (car mapping)
                    (if semantics
                        (matugen-theme--ensure-contrast
                         (or (alist-get (car mapping) palette) (cdr mapping)) backgrounds nil 4.5)
                      fg)) roles))
      roles)))

;;; Apply: no font reloads, Solaire toggles or repeated activation cycles.

(deftheme matugen "Matugen palette with semantic roles and explicit contrast checks.")
(provide-theme 'matugen)

(defun matugen-theme--options-key ()
  "Return settings that affect rendered faces."
  (list matugen-theme-style matugen-theme-palette matugen-theme-emphasis
        matugen-theme-semantic-colors matugen-theme-heading-scale))

(defun matugen-theme-color (role)
  "Return the currently applied semantic color ROLE, or nil before first load."
  (alist-get role matugen-theme--roles))

(defun matugen-theme-minimal-p ()
  "Return non-nil when the effective emphasis policy is minimal."
  (eq (cadr (matugen-theme--policy)) 'minimal))

(defun matugen-theme--sync-frame (frame)
  "Synchronize FRAME with the active Matugen background."
  (when (and matugen-theme--roles (custom-theme-enabled-p 'matugen) (frame-live-p frame))
    (let ((mode (if (matugen-theme--is-dark-color (alist-get 'surface matugen-theme--roles))
                    'dark 'light)))
      (set-frame-parameter frame 'background-mode mode)
      (frame-set-background-mode frame))))

(defun matugen-theme--apply-palette (palette &optional force)
  "Apply PALETTE if it or the options changed; FORCE also reapplies faces."
  (let ((key (cons palette (matugen-theme--options-key))))
    (when (or force (not (equal key matugen-theme--last-key))
              (not (custom-theme-enabled-p 'matugen)))
      ;; All fallible color calculations finish before changing any theme.
      (let* ((roles (matugen-theme--build-roles palette))
             (faces (matugen-theme-faces-build roles)))
        (apply #'custom-theme-set-faces 'matugen faces)
        (unless (custom-theme-enabled-p 'matugen)
          (mapc #'disable-theme (copy-sequence custom-enabled-themes))
          (enable-theme 'matugen))
        (setq matugen-theme--roles roles matugen-theme--last-key key)
        (when (boundp 'doom-theme) (setq doom-theme 'matugen))
        (mapc #'matugen-theme--sync-frame (frame-list))
        (run-hook-wrapped
         'matugen-theme-after-apply-hook
         (lambda (function)
           (condition-case err (funcall function)
             (error (message "Matugen after-apply hook: %s" (error-message-string err))))
           nil))
        t))))

;;;###autoload
(defun matugen-theme-reload (&optional force)
  "Read and apply the palette.  With prefix FORCE, reapply unchanged colors.
On invalid input preserve the last valid theme and return nil."
  (interactive "P")
  (condition-case err
      (let* ((palette (matugen-theme--read-palette))
             (changed (matugen-theme--apply-palette palette force)))
        (setq matugen-theme--last-palette palette matugen-theme--last-error nil
              matugen-theme--retry-count 0)
        (when (called-interactively-p 'interactive)
          (message "Matugen: %s (%s)" (if changed "updated" "unchanged") matugen-theme-style))
        t)
    (error
     (let ((message-text (error-message-string err)))
       (when (or (called-interactively-p 'interactive)
                 (not (equal message-text matugen-theme--last-error)))
         (message "Matugen: keeping the previous theme; %s" message-text))
       (setq matugen-theme--last-error message-text))
     nil)))

;;; Observers: track primary and fallback directories; recover via cheap polling.

(defun matugen-theme--paths ()
  "Return normalized primary and optional fallback paths."
  (delete-dups (mapcar #'expand-file-name
                       (delq nil (list matugen-theme-colors-file matugen-theme-fallback-colors-file)))))

(defun matugen-theme--state ()
  "Return the file identity and attributes needed to detect replacement or writes."
  (mapcar (lambda (path)
            (let ((attrs (file-attributes path 'integer)))
              (list path (nth 5 attrs) (nth 6 attrs) (nth 7 attrs) (nth 10 attrs))))
          (matugen-theme--paths)))

(defun matugen-theme--ensure-watches ()
  "Reconcile observers with existing directories, retaining valid descriptors."
  (let ((dirs (delete-dups (mapcar #'file-name-directory (matugen-theme--paths)))) kept)
    (dolist (watch matugen-theme--watches)
      (if (and (member (car watch) dirs) (file-notify-valid-p (cdr watch)))
          (push watch kept)
        (ignore-errors (file-notify-rm-watch (cdr watch)))))
    (setq matugen-theme--watches kept)
    (dolist (dir dirs)
      (when (and (file-directory-p dir) (not (assoc dir matugen-theme--watches)))
        (condition-case err
            (push (cons dir (file-notify-add-watch dir '(change)
                                                 #'matugen-theme--watcher-callback))
                  matugen-theme--watches)
          (file-notify-error
           (unless (equal err matugen-theme--watch-error)
             (message "Matugen: using polling for %s (%s)" dir (error-message-string err)))
           (setq matugen-theme--watch-error err)))))))

(defun matugen-theme--schedule (&optional retry)
  "Debounce a refresh.  RETRY preserves the bounded retry counter."
  (when matugen-theme-mode
    (unless retry (setq matugen-theme--retry-count 0))
    (when (timerp matugen-theme--timer) (cancel-timer matugen-theme--timer))
    (setq matugen-theme--timer
          (run-at-time (max 0.01 matugen-theme-update-delay) nil
                       #'matugen-theme--refresh matugen-theme--generation))))

(defun matugen-theme--refresh (generation)
  "Refresh for lifecycle GENERATION, retrying incomplete writes at most twice."
  (when (and matugen-theme-mode (= generation matugen-theme--generation))
    (setq matugen-theme--timer nil)
    (unless matugen-theme--previewing
      (matugen-theme--ensure-watches)
      (setq matugen-theme--file-state (matugen-theme--state))
      (unless (matugen-theme-reload)
        (when (< matugen-theme--retry-count 2)
          (cl-incf matugen-theme--retry-count)
          (matugen-theme--schedule t))))))

(defun matugen-theme--watcher-callback (event)
  "Handle both sides of rename EVENT and observer shutdown."
  (when matugen-theme-mode
    (let ((action (nth 1 event)) (paths (matugen-theme--paths)))
      (when (or (eq action 'stopped)
                (and (memq action '(created changed renamed deleted attribute-changed))
                     (cl-some (lambda (path)
                                (and (stringp path) (member (expand-file-name path) paths)))
                              (cddr event))))
        (matugen-theme--schedule)))))

(defun matugen-theme--poll ()
  "Recover observers and refresh only if inputs or rendering options changed."
  (when matugen-theme-mode
    (matugen-theme--ensure-watches)
    (let ((state (matugen-theme--state)))
      (when (or (not (equal state matugen-theme--file-state))
                (not (equal (cdr matugen-theme--last-key) (matugen-theme--options-key))))
        (setq matugen-theme--file-state state)
        (matugen-theme--schedule)))))

(defun matugen-theme--startup ()
  "Schedule the first application after initialization."
  (remove-hook 'emacs-startup-hook #'matugen-theme--startup)
  (matugen-theme--schedule))

(defun matugen-theme-mode-disable ()
  "Release observers, hooks and pending timers without changing current colors."
  (cl-incf matugen-theme--generation)
  (remove-hook 'emacs-startup-hook #'matugen-theme--startup)
  (remove-hook 'after-make-frame-functions #'matugen-theme--sync-frame)
  (dolist (timer (list matugen-theme--timer matugen-theme--poll-timer))
    (when (timerp timer) (cancel-timer timer)))
  (setq matugen-theme--timer nil matugen-theme--poll-timer nil)
  ;; Disable the callback while rm-watch emits `stopped' notifications.
  (let ((matugen-theme-mode nil))
    (dolist (watch matugen-theme--watches)
      (ignore-errors (file-notify-rm-watch (cdr watch)))))
  (setq matugen-theme--watches nil))

;;;###autoload
(define-minor-mode matugen-theme-mode
  "Globally follow validated Matugen palettes; disabling freezes current colors."
  :global t :lighter nil
  (matugen-theme-mode-disable)
  (when matugen-theme-mode
    (setq matugen-theme--file-state nil matugen-theme--retry-count 0)
    (matugen-theme--ensure-watches)
    (add-hook 'after-make-frame-functions #'matugen-theme--sync-frame)
    (setq matugen-theme--poll-timer
          (run-at-time (max 1 matugen-theme-poll-interval)
                       (max 1 matugen-theme-poll-interval) #'matugen-theme--poll))
    (if after-init-time (matugen-theme--schedule)
      (add-hook 'emacs-startup-hook #'matugen-theme--startup))))

;;; Preview: apply cached data and restore both style and themes on cancellation.

;;;###autoload
(defun matugen-theme-select-style ()
  "Preview presets and apply a selection for this session.
Canceling restores the original style and active themes.  Palette/emphasis
overrides still apply.  Customize `matugen-theme-style' to persist a choice."
  (interactive)
  (let* ((original matugen-theme-style)
         (themes (copy-sequence custom-enabled-themes))
         (doom-was-bound (boundp 'doom-theme))
         (old-doom (and doom-was-bound doom-theme))
         (frames (mapcar (lambda (f) (cons f (frame-parameter f 'background-mode))) (frame-list)))
         (palette (or matugen-theme--last-palette (matugen-theme--read-palette)))
         (names (mapcar (lambda (p) (symbol-name (car p))) matugen-theme--profiles))
         (matugen-theme--previewing t)
         committed)
    (cl-labels ((restore ()
                  (setq matugen-theme-style original)
                  (matugen-theme--apply-palette palette)
                  (unless (equal custom-enabled-themes themes)
                    (mapc #'disable-theme (copy-sequence custom-enabled-themes))
                    (mapc #'enable-theme (reverse themes)))
                  (when doom-was-bound (setq doom-theme old-doom))
                  (dolist (item frames)
                    (when (frame-live-p (car item))
                      (set-frame-parameter (car item) 'background-mode (cdr item))
                      (frame-set-background-mode (car item))))))
      (unwind-protect
          (let ((selected
                 (if (require 'consult nil t)
                     (consult--read names :prompt "Matugen profile: " :require-match t
                                    :state (lambda (action candidate)
                                             (when (eq action 'preview)
                                               (if (null candidate) (restore)
                                                 (setq matugen-theme-style (intern candidate))
                                                 (matugen-theme--apply-palette palette)))))
                   (completing-read "Matugen profile: " names nil t))))
            (when selected
              (setq matugen-theme-style (intern selected))
              (matugen-theme--apply-palette palette)
              (setq committed t)))
        (unless committed (restore))
        ;; Canceling from another active theme must not immediately take it
        ;; over again merely because the selector was opened.
        (when (or committed (memq 'matugen themes))
          (matugen-theme--schedule))))))

(provide 'matugen-theme)
;;; matugen-theme.el ends here
