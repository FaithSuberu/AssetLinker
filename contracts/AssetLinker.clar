
;; Contract: RWAx Fractional Vault
;; Purpose : Tokenized RWA with compliance, dividends, NAV redeem/reinvest
;; License : MIT
;; ============================================================

;; ---------- SIP-010 Fungible Token ----------
(define-fungible-token rwax)

;; ---------- Constants / Params ----------
(define-constant SCALAR u1000000)         ;; dividends-per-share precision
(define-constant MAX-SUPPLY (* u1000000000 u1000000)) ;; 1B tokens, 6 decimals
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_FORBIDDEN (err u101))
(define-constant ERR_INVALID (err u102))
(define-constant ERR_BALANCE (err u103))
(define-constant ERR_CAPPED (err u104))
(define-constant ERR_PAUSED (err u105))
(define-constant ERR_LOCKED (err u106))
(define-constant ERR_ZERO (err u107))
(define-constant ERR_DPS (err u108))
(define-constant ERR_NAV (err u109))
(define-constant ERR_BLACKLIST (err u110))
(define-constant ERR_KYC (err u111))

;; ---------- Ownership & Roles ----------
(define-data-var contract-owner principal tx-sender)
(define-map operators principal bool)
(define-map auditors principal bool)

(define-private (only-owner) 
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    (ok true)))
(define-private (only-operator)
  (begin
    (asserts! (or (is-eq tx-sender (var-get contract-owner))
                  (default-to false (map-get? operators tx-sender))) ERR_UNAUTHORIZED)
    (ok true)))
(define-private (only-auditor)
  (begin
    (asserts! (or (is-eq tx-sender (var-get contract-owner))
                  (default-to false (map-get? auditors tx-sender))) ERR_UNAUTHORIZED)
    (ok true)))

;; ---------- Compliance / Controls ----------
(define-data-var transfers-paused bool false)
(define-map kyc-allow principal bool)
(define-map blacklist principal bool)
(define-map lockups principal uint) ;; unlock-height

;; ---------- Token Supply Meta ----------
(define-data-var total-supply uint u0)
(define-data-var token-name (string-utf8 64) u"RealWorldAsset Shares")
(define-data-var token-symbol (string-utf8 12) u"RWAx")
(define-data-var token-decimals uint u6)
(define-data-var token-uri (optional (string-utf8 256)) none)

;; ---------- Dividends State ----------
(define-data-var dividends-per-share uint u0)                       ;; cumulative
(define-map dps-paid principal uint)                                 ;; user -> lastDPS
(define-data-var total-dividends-received uint u0)
(define-data-var total-dividends-paid uint u0)

;; ---------- NAV / Fees ----------
(define-data-var nav-microstx-per-token uint u0)     ;; price per token in micro-STX
(define-data-var mgmt-fee-bps uint u0)               ;; mgmt fee on dividend deposits/redeems
(define-data-var fee-recipient principal (var-get contract-owner))

;; ---------- Snapshots ----------
(define-data-var next-snapshot-id uint u1)
(define-map snapshots uint {
  block: uint,
  supply: uint,
  dps: uint
})

;; ============================================================
;; Helpers
;; ============================================================

(define-read-only (ft-name)  (ok (var-get token-name)))
(define-read-only (ft-symbol) (ok (var-get token-symbol)))
(define-read-only (ft-decimals) (ok (var-get token-decimals)))
(define-read-only (get-total-supply) (ok (var-get total-supply)))
(define-read-only (balance-of (who principal)) (ok (ft-get-balance rwax who)))
(define-read-only (get-dps) (ok (var-get dividends-per-share)))
(define-read-only (get-nav) (ok (var-get nav-microstx-per-token)))
(define-read-only (is-paused) (ok (var-get transfers-paused)))
(define-read-only (is-kyc (who principal)) (ok (default-to false (map-get? kyc-allow who))))
(define-read-only (is-blacklisted (who principal)) (ok (default-to false (map-get? blacklist who))))
(define-read-only (get-lockup (who principal)) (ok (default-to u0 (map-get? lockups who))))
(define-read-only (get-token-uri) (ok (var-get token-uri)))

(define-private (require-transfer-ok (from principal) (to principal))
  (begin
    (asserts! (not (var-get transfers-paused)) ERR_PAUSED)
    (asserts! (not (default-to false (map-get? blacklist from))) ERR_BLACKLIST)
    (asserts! (not (default-to false (map-get? blacklist to))) ERR_BLACKLIST)
    (let ((unlock (default-to u0 (map-get? lockups from))))
      (asserts! (>= stacks-block-height unlock) ERR_LOCKED))
    ;; KYC rule: both sides must be KYC'd (except owner/operator moving admin balances)
    ;; Check sender KYC
    (if (not (or (is-eq from (var-get contract-owner)) 
                 (default-to false (map-get? operators from))))
        (asserts! (default-to false (map-get? kyc-allow from)) ERR_KYC)
        true)
    ;; Check recipient KYC
    (if (not (or (is-eq to (var-get contract-owner))
                 (default-to false (map-get? operators to))))
        (asserts! (default-to false (map-get? kyc-allow to)) ERR_KYC)
        true)
    (ok true)))

;; ============================================================
;; Admin & Roles
;; ============================================================

(define-public (set-operator (who principal) (on bool))
  (begin 
    (try! (only-owner))
    (map-set operators who on) 
    (ok on)))

(define-public (set-auditor (who principal) (on bool))
  (begin 
    (try! (only-owner))
    (map-set auditors who on)
    (ok on)))

(define-public (transfer-ownership (new principal))
  (begin 
    (try! (only-owner))
    (ok (var-set contract-owner new))))

(define-public (set-uri (u (string-utf8 256)))
  (begin 
    (try! (only-owner))
    (var-set token-uri (some u))
    (ok true)))

(define-public (set-pause (p bool))
  (begin
    (try! (only-owner))
    (var-set transfers-paused p)
    (ok p)))

(define-public (kyc-set (who principal) (on bool))
  (begin 
    (try! (only-operator))
    (map-set kyc-allow who on)
    (ok on)))

(define-public (kyc-batch (users (list 200 principal)) (on bool))
  (begin 
    (try! (only-operator))
    (map kyc-batch-helper users)
    (ok on)))
(define-private (kyc-batch-helper (who principal))
  (begin (map-set kyc-allow who true) true))

(define-public (blacklist-set (who principal) (on bool))
  (begin 
    (try! (only-owner))
    (map-set blacklist who on)
    (ok on)))

(define-public (set-lockup (who principal) (unlock-height uint))
  (begin 
    (try! (only-operator))
    (map-set lockups who unlock-height)
    (ok unlock-height)))

(define-public (lock-batch (pairs (list 200 (tuple (who principal) (unlock uint)))))
  (begin 
    (try! (only-operator))
    (map lock-helper pairs)
    (ok true)))
(define-private (lock-helper (t (tuple (who principal) (unlock uint))))
  (begin (map-set lockups (get who t) (get unlock t)) true))

(define-public (set-fees (bps uint) (recipient principal))
  (begin 
    (try! (only-owner))
    (var-set mgmt-fee-bps bps)
    (var-set fee-recipient recipient)
    (ok true)))

(define-public (set-nav (price uint))
  (begin 
    (try! (only-auditor))
    (asserts! (> price u0) ERR_NAV)
    (var-set nav-microstx-per-token price)
    (print {event: "NAVUpdated", price: price, by: tx-sender})
    (ok true)))

;; ============================================================
;; Mint / Burn (capped, role-based)
;; ============================================================

(define-public (mint (to principal) (amount uint))
  (begin
    (try! (only-operator))
    (asserts! (> amount u0) ERR_ZERO)
    (asserts! (<= (+ (var-get total-supply) amount) MAX-SUPPLY) ERR_CAPPED)
    (unwrap! (ft-mint? rwax amount to) ERR_INVALID)
    (var-set total-supply (+ (var-get total-supply) amount))
    (ok true)))

(define-public (burn (from principal) (amount uint))
  (begin
    (try! (only-operator))
    (asserts! (> amount u0) ERR_ZERO)
    (unwrap! (ft-burn? rwax amount from) ERR_INVALID)
    (var-set total-supply (- (var-get total-supply) amount))
    (ok true)))

(define-public (mint-batch (items (list 200 (tuple (to principal) (amt uint)))))
  (begin 
    (try! (only-operator))
    (let ((sum (fold + (map get-amt items) u0)))
      (asserts! (> sum u0) ERR_ZERO)
      (asserts! (<= (+ (var-get total-supply) sum) MAX-SUPPLY) ERR_CAPPED)
      (map mint-helper items)
      (var-set total-supply (+ (var-get total-supply) sum))
      (ok true))))
(define-private (get-amt (t (tuple (to principal) (amt uint)))) (get amt t))
(define-private (mint-helper (t (tuple (to principal) (amt uint))))
  (match (ft-mint? rwax (get amt t) (get to t))
    success (ok true)
    error (err ERR_INVALID)))

;; ============================================================
;; Transfers (SIP-010 surface + compliance hook)
;; ============================================================

(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
  (begin
    (try! (require-transfer-ok sender recipient))
    (asserts! (<= amount (ft-get-balance rwax sender)) ERR_BALANCE)
    (ft-transfer? rwax amount sender recipient)))

;; ============================================================
;; Dividends: Deposit, Claim, Reinvest
;; ============================================================

;; deposit STX to contract and increase DPS = amount / supply
(define-public (deposit-dividends (amount uint))
  (begin
    (try! (only-operator))
    (asserts! (> amount u0) ERR_ZERO)
    (let ((supply (var-get total-supply)))
      (asserts! (> supply u0) ERR_DPS)
      ;; collect STX into contract
      (unwrap! (stx-transfer? amount tx-sender (as-contract tx-sender)) ERR_INVALID)
      ;; mgmt fee
      (let ((fee (/ (* amount (var-get mgmt-fee-bps)) u10000))
            (net (- amount (/ (* amount (var-get mgmt-fee-bps)) u10000))))
        (if (> fee u0) (unwrap! (stx-transfer? fee (as-contract tx-sender) (var-get fee-recipient)) ERR_INVALID) true)
        (let ((inc (/ (* net SCALAR) supply)))
          (var-set dividends-per-share (+ (var-get dividends-per-share) inc))
          (var-set total-dividends-received (+ (var-get total-dividends-received) net))
          (print {event:"DividendsDeposited", gross: amount, fee: fee, net: net, dps: (var-get dividends-per-share)})
          (ok true))))))

;; view: pending dividends in STX for user
(define-read-only (pending-dividends (user principal))
  (let ((bal (ft-get-balance rwax user))
        (cur (var-get dividends-per-share))
        (paid (default-to u0 (map-get? dps-paid user))))
    (ok (/ (* bal (- cur paid)) SCALAR))))

;; claim owed STX
(define-public (claim-dividends)
  (let ((bal (ft-get-balance rwax tx-sender))
        (cur (var-get dividends-per-share))
        (paid (default-to u0 (map-get? dps-paid tx-sender))))
    (begin
      (asserts! (> bal u0) ERR_BALANCE)
      (let ((owed (/ (* bal (- cur paid)) SCALAR)))
        (asserts! (> owed u0) ERR_ZERO)
        (map-set dps-paid tx-sender cur)
        (unwrap! (stx-transfer? owed (as-contract tx-sender) tx-sender) ERR_INVALID)
        (var-set total-dividends-paid (+ (var-get total-dividends-paid) owed))
        (print {event:"DividendsClaimed", user: tx-sender, amount: owed})
        (ok owed)))))

;; reinvest owed dividends into more tokens at NAV
(define-public (reinvest-dividends)
  (let ((nav (var-get nav-microstx-per-token)))
    (begin
      (asserts! (> nav u0) ERR_NAV)
      (let ((owed (unwrap! (pending-dividends tx-sender) ERR_INVALID)))
        (asserts! (> owed u0) ERR_ZERO)
        ;; mark paid
        (map-set dps-paid tx-sender (var-get dividends-per-share))
        ;; tokens to mint = owed / nav
        (let ((tokens (/ owed nav)))
          (asserts! (> tokens u0) ERR_ZERO)
          (unwrap! (ft-mint? rwax tokens tx-sender) ERR_INVALID)
          (var-set total-supply (+ (var-get total-supply) tokens))
          ;; keep STX in contract treasury to back tokens (no transfer out)
          (print {event:"DividendsReinvested", user: tx-sender, stx: owed, tokens: tokens, nav: nav})
          (ok tokens))))))

;; redeem tokens back to STX at NAV (minus fee)
(define-public (redeem (amount uint))
  (begin
    (asserts! (> amount u0) ERR_ZERO)
    (let ((nav (var-get nav-microstx-per-token)))
      (asserts! (> nav u0) ERR_NAV)
      (asserts! (<= amount (ft-get-balance rwax tx-sender)) ERR_BALANCE)
      (let ((gross (* amount nav))
            (fee (/ (* (* amount nav) (var-get mgmt-fee-bps)) u10000))
            (net (- (* amount nav) (/ (* (* amount nav) (var-get mgmt-fee-bps)) u10000))))
        (unwrap! (ft-burn? rwax amount tx-sender) ERR_INVALID)
        (var-set total-supply (- (var-get total-supply) amount))
        (if (> fee u0) (unwrap! (stx-transfer? fee (as-contract tx-sender) (var-get fee-recipient)) ERR_INVALID) true)
        (unwrap! (stx-transfer? net (as-contract tx-sender) tx-sender) ERR_INVALID)
        (print {event:"Redeemed", user: tx-sender, tokens: amount, gross: gross, fee: fee, net: net, nav: nav})
        (ok net)))))

;; ============================================================
;; Snapshots (auditability / airdrops / governance baselines)
;; ============================================================

(define-public (snapshot)
  (begin
    (try! (only-auditor))
    (let ((id (var-get next-snapshot-id)))
      (map-set snapshots id { block: stacks-block-height, supply: (var-get total-supply), dps: (var-get dividends-per-share) })
      (var-set next-snapshot-id (+ id u1))
      (print {event:"Snapshot", id: id})
      (ok id))))

(define-read-only (get-snapshot (id uint))
  (map-get? snapshots id))

;; ============================================================
;; Auditor-safe Treasury View
;; ============================================================

(define-read-only (treasury-balance)
  (ok (stx-get-balance (as-contract tx-sender))))

(define-read-only (dividend-stats)
  (ok {
    total-received: (var-get total-dividends-received),
    total-paid: (var-get total-dividends-paid),
    dps: (var-get dividends-per-share)
  }))

;; ============================================================
;; Quality-of-life: Batch transfers and admin sweeps
;; ============================================================

(define-public (transfer-batch (items (list 200 (tuple (from principal) (to principal) (amt uint)))))
  (begin
    (map transfer-batch-helper items)
    (ok true)))
(define-private (transfer-batch-helper (t (tuple (from principal) (to principal) (amt uint))))
  (begin
    (try! (require-transfer-ok (get from t) (get to t)))
    (ok (unwrap! (ft-transfer? rwax (get amt t) (get from t) (get to t)) ERR_INVALID))))

;; Sweep any excess STX (beyond obligations) to fee-recipient (owner/ops)
;; NOTE: Keep conservative; this example just allows owner to move arbitrary amount.
(define-public (treasury-withdraw (amount uint) (to principal))
  (begin 
    (try! (only-owner))
    (asserts! (> amount u0) ERR_ZERO)
    (unwrap! (stx-transfer? amount (as-contract tx-sender) to) ERR_INVALID)
    (print {event:"TreasuryWithdraw", to: to, amount: amount})
    (ok true)))
