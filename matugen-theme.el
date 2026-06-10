;;; matugen-theme.el --- Dynamic theme switcher using Matugen colors -*- lexical-binding: t -*-

;; Copyright (C) 2026 Diego

;; Author: Diego
;; Maintainer: Diego
;; Version: 0.5.0
;; Package-Requires: ((emacs "28.1") (modus-themes "4.0"))
;; Keywords: themes, matugen, wayland, ricing

;;; Commentary:

;; Este paquete permite integrar la paleta de colores de Ghostty (dankcolors)
;; generada por Matugen/Wallust en Adank Linux directamente con Emacs.
;; Incorpora ajustes de legibilidad (aclarado/oscurecido) para mantener el
;; contraste AAA de Modus Themes, y detección de luminancia para cambiar de
;; modo claro a oscuro automáticamente.

;;; Code:

(require 'filenotify)
(require 'modus-themes)
(require 'color)

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

(defun matugen-theme--mod-color (hex percent lighten)
  "Aclara u oscurece un HEX un PERCENT (0-100).
Si LIGHTEN es no-nil aclara, si es nil oscurece."
  (if lighten
      (color-lighten-name hex percent)
    (color-darken-name hex percent)))

(defun matugen-theme--is-dark-color (hex)
  "Retorna t si el color HEX es oscuro basándose en luminancia."
  (let* ((rgb (color-name-to-rgb hex))
         (r (nth 0 rgb))
         (g (nth 1 rgb))
         (b (nth 2 rgb))
         ;; Fórmula simple de luminancia para sRGB (0.0 a 1.0)
         (lum (+ (* 0.299 r) (* 0.587 g) (* 0.114 b))))
    (< lum 0.5)))

;;;###autoload
(defun matugen-theme-reload ()
  "Recarga la paleta leyendo el archivo dankcolors y aplicándolo a modus-themes."
  (interactive)
  (let ((colors (matugen-theme--read-dankcolors)))
    (when colors
      (let* ((bg (cdr (assq 'background colors)))
             (fg (cdr (assq 'foreground colors)))
             (primary (cdr (assq 'palette-4 colors)))   ;; Blue
             (secondary (cdr (assq 'palette-6 colors))) ;; Cyan
             (tertiary (cdr (assq 'palette-5 colors)))  ;; Magenta
             (error (cdr (assq 'palette-1 colors)))     ;; Red
             (green (cdr (assq 'palette-2 colors)))     ;; Green
             (yellow (cdr (assq 'palette-3 colors)))    ;; Yellow
             
             ;; Lógica de Tema Automático: 
             ;; Determinamos si la paleta que exportó Linux es oscura o clara
             ;; calculando la luminancia del color 'background'.
             (is-dark (matugen-theme--is-dark-color bg))
             ;; En base a eso, obligamos a Emacs a adoptar el tema adecuado.
             (base-theme (if is-dark 'modus-vivendi 'modus-operandi))
             
             (bg-dim (matugen-theme--mod-color bg 5 is-dark))
             (bg-alt (matugen-theme--mod-color bg 10 is-dark))
             (bg-active (matugen-theme--mod-color bg 15 is-dark))
             
             ;; Para las barras y el cursor, queremos variaciones notorias del fondo
             (bg-hl (matugen-theme--mod-color bg 8 is-dark))
             (bg-region (matugen-theme--mod-color bg 20 is-dark))
             (bg-mode-active (matugen-theme--mod-color bg 25 is-dark))
             (bg-mode-inactive (matugen-theme--mod-color bg 12 is-dark))
             (border-mode (matugen-theme--mod-color bg 30 is-dark))
             
             (fg-dim (matugen-theme--mod-color fg 20 (not is-dark))))
        
        ;; Ajuste de paleta con cálculos matemáticos
        (setq modus-themes-common-palette-overrides
              `((bg-main ,bg)
                (fg-main ,fg)
                (bg-dim ,bg-dim)
                (bg-alt ,bg-alt)
                (bg-active ,bg-active)
                (bg-inactive ,bg-dim)
                (border ,bg-alt)
                (fg-dim ,fg-dim)
                
                ;; Resaltados e Interfaz Inferior
                (bg-hl-line ,bg-hl)
                (bg-region ,bg-region)
                (bg-mode-line-active ,bg-mode-active)
                (bg-mode-line-inactive ,bg-mode-inactive)
                (border-mode-line-active ,border-mode)
                (border-mode-line-inactive ,border-mode)
                
                ;; Colores semánticos base
                (blue ,primary)
                (cyan ,secondary)
                (magenta ,tertiary)
                (red ,error)
                (green ,green)
                (yellow ,yellow)
                
                ;; Variantes para legibilidad
                (blue-cooler ,(matugen-theme--mod-color primary 15 nil))
                (blue-warmer ,(matugen-theme--mod-color primary 15 t))
                (magenta-cooler ,(matugen-theme--mod-color tertiary 15 nil))
                (magenta-warmer ,(matugen-theme--mod-color tertiary 15 t))
                (red-cooler ,(matugen-theme--mod-color error 15 nil))
                (red-warmer ,(matugen-theme--mod-color error 15 t))
                (green-cooler ,(matugen-theme--mod-color green 15 nil))
                (green-warmer ,(matugen-theme--mod-color green 15 t))
                (yellow-cooler ,(matugen-theme--mod-color yellow 15 nil))
                (yellow-warmer ,(matugen-theme--mod-color yellow 15 t))))
        
        ;; Limpiamos TODOS los temas para evitar que caras antiguas colisionen (el "bug del cursor oscuro")
        (mapc #'disable-theme custom-enabled-themes)
        (modus-themes-load-theme base-theme)
        
        (when (fboundp 'doom/reload-theme)
          (doom/reload-theme))
        (when (featurep 'solaire-mode)
          (solaire-global-mode -1)
          (solaire-global-mode 1))
          
        (message "Matugen: Color palette applied.")))))

(defun matugen-theme--watcher-callback (event)
  "Callback que se ejecuta cuando el archivo de colores cambia."
  (let ((file (nth 2 event)))
    (when (and (stringp file)
               (string= (file-name-nondirectory file)
                        (file-name-nondirectory matugen-theme-colors-file)))
      (matugen-theme-reload))))

;;;###autoload
(define-minor-mode matugen-theme-mode
  "Minor mode global para sincronizar Emacs con los colores de Ghostty / Adank Linux."
  :global t
  :lighter " Matugen"
  (if matugen-theme-mode
      (progn
        (when (file-exists-p matugen-theme-colors-file)
          (if after-init-time
              (matugen-theme-reload)
            (add-hook 'emacs-startup-hook #'matugen-theme-reload)))
        
        (unless matugen-theme--file-watch-descriptor
          (let ((dir (file-name-directory matugen-theme-colors-file)))
            (unless (file-exists-p dir)
              (make-directory dir t))
            (setq matugen-theme--file-watch-descriptor
                  (file-notify-add-watch dir
                                         '(change attribute-change)
                                         #'matugen-theme--watcher-callback)))))
    (when matugen-theme--file-watch-descriptor
      (file-notify-rm-watch matugen-theme--file-watch-descriptor)
      (setq matugen-theme--file-watch-descriptor nil))))

(provide 'matugen-theme)
;;; matugen-theme.el ends here
