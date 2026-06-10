;;; matugen-theme.el --- Dynamic theme switcher using Matugen colors -*- lexical-binding: t -*-

;; Copyright (C) 2026 Diego

;; Author: Diego
;; Maintainer: Diego
;; Version: 0.3.2
;; Package-Requires: ((emacs "28.1") (modus-themes "4.0"))
;; Keywords: themes, matugen, wayland, ricing

;;; Commentary:

;; Este paquete permite integrar la paleta de colores de Ghostty (dankcolors)
;; generada por Matugen/Wallust en Adank Linux directamente con Emacs.

;;; Code:

(require 'filenotify)
(require 'modus-themes)

(defgroup matugen-theme nil
  "Dynamic theme switcher based on Ghostty dankcolors (Adank Linux)."
  :group 'modus-themes
  :prefix "matugen-theme-")

(defcustom matugen-theme-colors-file (expand-file-name "~/.config/ghostty/themes/dankcolors")
  "Ruta al archivo de colores dankcolors de Ghostty."
  :type 'file
  :group 'matugen-theme)

(defvar matugen-theme--file-watch-descriptor nil
  "Descriptor para el file watcher.")

(defun matugen-theme--read-dankcolors ()
  "Lee el archivo de dankcolors y lo devuelve como alist."
  (when (file-exists-p matugen-theme-colors-file)
    (let ((colors nil))
      (with-temp-buffer
        (insert-file-contents matugen-theme-colors-file)
        (goto-char (point-min))
        (while (re-search-forward "^\\([a-z-]+\\) = \\(#[0-9a-fA-F]+\\)" nil t)
          (push (cons (intern (match-string 1)) (match-string 2)) colors))
        (goto-char (point-min))
        (while (re-search-forward "^palette = \\([0-9]+\\)=\\(#[0-9a-fA-F]+\\)" nil t)
          (push (cons (intern (format "palette-%s" (match-string 1))) (match-string 2)) colors)))
      colors)))

;;;###autoload
(defun matugen-theme-reload ()
  "Recarga la paleta leyendo el archivo dankcolors y aplicándolo a modus-themes."
  (interactive)
  (let ((colors (matugen-theme--read-dankcolors))
        ;; Determinar el tema activo sin depender de funciones privadas obsoletas
        (base-theme (if (memq 'modus-operandi custom-enabled-themes)
                        'modus-operandi
                      'modus-vivendi)))
    (when colors
      (let ((bg (cdr (assq 'background colors)))
            (fg (cdr (assq 'foreground colors)))
            (primary (cdr (assq 'palette-4 colors)))   ;; Blue
            (secondary (cdr (assq 'palette-6 colors))) ;; Cyan
            (tertiary (cdr (assq 'palette-5 colors)))  ;; Magenta
            (error (cdr (assq 'palette-1 colors)))     ;; Red
            (surface (cdr (assq 'palette-0 colors)))   ;; Black (Dim/Background alternative)
            (surface-var (cdr (assq 'selection-background colors))))
        
        ;; Ajuste: Si ghostty manda un fondo oscuro, usamos vivendi
        (setq modus-themes-common-palette-overrides
              `((bg-main ,bg)
                (fg-main ,fg)
                (bg-dim ,surface)
                (bg-alt ,surface-var)
                (border ,surface-var)
                (blue ,primary)
                (cyan ,secondary)
                (magenta ,tertiary)
                (red ,error)
                (blue-cooler ,primary)
                (blue-warmer ,secondary)
                (magenta-cooler ,tertiary)))
        
        (disable-theme base-theme)
        (modus-themes-load-theme base-theme)
        
        ;; Forzar a Doom Emacs a actualizar sus propios paquetes y buffers (como Solaire-mode)
        (when (fboundp 'doom/reload-theme)
          (doom/reload-theme))
        (when (featurep 'solaire-mode)
          (solaire-global-mode -1)
          (solaire-global-mode 1))
          
        (message "Matugen (Dank Linux): Paleta de colores aplicada.")))))

(defun matugen-theme--watcher-callback (event)
  "Callback que se ejecuta cuando el archivo de colores cambia."
  (when (memq (nth 1 event) '(changed attribute-changed created))
    (matugen-theme-reload)))

;;;###autoload
(define-minor-mode matugen-theme-mode
  "Minor mode global para sincronizar Emacs con los colores de Ghostty / Adank Linux."
  :global t
  :lighter " Matugen"
  (if matugen-theme-mode
      (progn
        (when (file-exists-p matugen-theme-colors-file)
          (matugen-theme-reload))
        (unless matugen-theme--file-watch-descriptor
          (let ((dir (file-name-directory matugen-theme-colors-file)))
            (unless (file-exists-p dir)
              (make-directory dir t)))
          (setq matugen-theme--file-watch-descriptor
                (file-notify-add-watch matugen-theme-colors-file
                                       '(change attribute-change)
                                       #'matugen-theme--watcher-callback))))
    (when matugen-theme--file-watch-descriptor
      (file-notify-rm-watch matugen-theme--file-watch-descriptor)
      (setq matugen-theme--file-watch-descriptor nil))))

(provide 'matugen-theme)
;;; matugen-theme.el ends here
