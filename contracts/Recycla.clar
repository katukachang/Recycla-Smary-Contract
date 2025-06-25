;; title: Recycla
;; version: 1.0.0
;; summary: Recycling Incentive Protocol - Reward users who report or recycle waste
;; description: A decentralized platform that incentivizes recycling by rewarding users with tokens for reporting waste locations and confirming recycling activities

;; traits

;; token definitions
(define-fungible-token recycla-token)

;; constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-insufficient-balance (err u103))
(define-constant err-invalid-amount (err u104))
(define-constant err-already-verified (err u105))
(define-constant err-cannot-verify-own (err u106))
(define-constant err-invalid-coordinates (err u107))
(define-constant err-reward-already-claimed (err u108))

(define-constant base-report-reward u100)
(define-constant base-recycle-reward u200)
(define-constant verification-reward u50)
(define-constant min-verifications u3)

;; data vars
(define-data-var next-report-id uint u1)
(define-data-var total-recycled uint u0)
(define-data-var contract-balance uint u0)

;; data maps
(define-map waste-reports
  uint
  {
    reporter: principal,
    location-lat: int,
    location-lng: int,
    waste-type: (string-ascii 50),
    amount: uint,
    timestamp: uint,
    verified: bool,
    verification-count: uint,
    reward-claimed: bool,
    recycled: bool
  }
)

(define-map user-profiles
  principal
  {
    total-reports: uint,
    total-recycled: uint,
    total-earned: uint,
    reputation-score: uint,
    last-activity: uint
  }
)

(define-map report-verifications
  { report-id: uint, verifier: principal }
  { verified: bool, timestamp: uint }
)

(define-map recycling-confirmations
  uint
  {
    recycler: principal,
    report-id: uint,
    timestamp: uint,
    confirmed: bool,
    confirmation-count: uint
  }
)

(define-map user-balances
  principal
  uint
)

;; public functions
(define-public (initialize-contract (initial-supply uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (try! (ft-mint? recycla-token initial-supply contract-owner))
    (var-set contract-balance initial-supply)
    (ok true)
  )
)

(define-public (report-waste (lat int) (lng int) (waste-type (string-ascii 50)) (amount uint))
  (let
    (
      (report-id (var-get next-report-id))
      (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    )
    (asserts! (and (>= lat -90000000) (<= lat 90000000)) err-invalid-coordinates)
    (asserts! (and (>= lng -180000000) (<= lng 180000000)) err-invalid-coordinates)
    (asserts! (> amount u0) err-invalid-amount)
    
    (map-set waste-reports report-id
      {
        reporter: tx-sender,
        location-lat: lat,
        location-lng: lng,
        waste-type: waste-type,
        amount: amount,
        timestamp: current-time,
        verified: false,
        verification-count: u0,
        reward-claimed: false,
        recycled: false
      }
    )
    
    (unwrap! (update-user-profile tx-sender u1 u0 u0) err-owner-only)
    (var-set next-report-id (+ report-id u1))
    (ok report-id)
  )
)

(define-public (verify-report (report-id uint))
  (let
    (
      (report (unwrap! (map-get? waste-reports report-id) err-not-found))
      (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
      (verification-key { report-id: report-id, verifier: tx-sender })
    )
    (asserts! (not (is-eq tx-sender (get reporter report))) err-cannot-verify-own)
    (asserts! (is-none (map-get? report-verifications verification-key)) err-already-verified)
    
    (map-set report-verifications verification-key
      { verified: true, timestamp: current-time }
    )
    
    (let
      (
        (new-verification-count (+ (get verification-count report) u1))
        (is-now-verified (>= new-verification-count min-verifications))
      )
      (map-set waste-reports report-id
        (merge report {
          verification-count: new-verification-count,
          verified: is-now-verified
        })
      )
      
      (try! (reward-user tx-sender verification-reward))
      (ok new-verification-count)
    )
  )
)

(define-public (confirm-recycling (report-id uint))
  (let
    (
      (report (unwrap! (map-get? waste-reports report-id) err-not-found))
      (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    )
    (asserts! (get verified report) err-not-found)
    (asserts! (not (get recycled report)) err-already-verified)
    
    (map-set waste-reports report-id
      (merge report { recycled: true })
    )
    
    (let
      (
        (recycling-reward (calculate-recycling-reward (get amount report)))
        (reporter-reward (calculate-report-reward (get amount report)))
      )
      (try! (reward-user tx-sender recycling-reward))
      (try! (reward-user (get reporter report) reporter-reward))
      
      (unwrap! (update-user-profile tx-sender u0 (get amount report) recycling-reward) err-owner-only)
      (unwrap! (update-user-profile (get reporter report) u0 u0 reporter-reward) err-owner-only)
      (var-set total-recycled (+ (var-get total-recycled) (get amount report)))
      
      (ok true)
    )
  )
)

(define-public (claim-report-reward (report-id uint))
  (let
    (
      (report (unwrap! (map-get? waste-reports report-id) err-not-found))
    )
    (asserts! (is-eq tx-sender (get reporter report)) err-owner-only)
    (asserts! (get verified report) err-not-found)
    (asserts! (not (get reward-claimed report)) err-reward-already-claimed)
    
    (map-set waste-reports report-id
      (merge report { reward-claimed: true })
    )
    
    (let
      (
        (reward-amount (calculate-report-reward (get amount report)))
      )
      (try! (reward-user tx-sender reward-amount))
      (ok reward-amount)
    )
  )
)

(define-public (transfer-tokens (recipient principal) (amount uint))
  (let
    (
      (sender-balance (default-to u0 (map-get? user-balances tx-sender)))
    )
    (asserts! (>= sender-balance amount) err-insufficient-balance)
    (asserts! (> amount u0) err-invalid-amount)
    
    (map-set user-balances tx-sender (- sender-balance amount))
    (map-set user-balances recipient 
      (+ (default-to u0 (map-get? user-balances recipient)) amount)
    )
    (ok true)
  )
)

;; read only functions
(define-read-only (get-report (report-id uint))
  (map-get? waste-reports report-id)
)

(define-read-only (get-user-profile (user principal))
  (map-get? user-profiles user)
)

(define-read-only (get-user-balance (user principal))
  (default-to u0 (map-get? user-balances user))
)

(define-read-only (get-total-recycled)
  (var-get total-recycled)
)

(define-read-only (get-contract-stats)
  {
    total-reports: (- (var-get next-report-id) u1),
    total-recycled: (var-get total-recycled),
    contract-balance: (var-get contract-balance)
  }
)

(define-read-only (get-verification-status (report-id uint) (verifier principal))
  (map-get? report-verifications { report-id: report-id, verifier: verifier })
)

(define-read-only (calculate-report-reward (amount uint))
  (+ base-report-reward (* amount u2))
)

(define-read-only (calculate-recycling-reward (amount uint))
  (+ base-recycle-reward (* amount u5))
)

(define-read-only (get-reputation-multiplier (user principal))
  (let
    (
      (profile (default-to 
        { total-reports: u0, total-recycled: u0, total-earned: u0, reputation-score: u0, last-activity: u0 }
        (map-get? user-profiles user)
      ))
    )
    (if (> (get reputation-score profile) u1000)
      u150
      (if (> (get reputation-score profile) u500)
        u125
        u100
      )
    )
  )
)

;; private functions
(define-private (reward-user (user principal) (amount uint))
  (let
    (
      (current-balance (default-to u0 (map-get? user-balances user)))
      (multiplier (get-reputation-multiplier user))
      (final-amount (/ (* amount multiplier) u100))
    )
    (asserts! (<= final-amount (var-get contract-balance)) err-insufficient-balance)
    
    (map-set user-balances user (+ current-balance final-amount))
    (var-set contract-balance (- (var-get contract-balance) final-amount))
    (ok final-amount)
  )
)

(define-private (update-user-profile (user principal) (reports-delta uint) (recycled-delta uint) (earned-delta uint))
  (let
    (
      (current-profile (default-to 
        { total-reports: u0, total-recycled: u0, total-earned: u0, reputation-score: u0, last-activity: u0 }
        (map-get? user-profiles user)
      ))
      (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
      (new-reputation (+ (get reputation-score current-profile) (* reports-delta u10) (* recycled-delta u20)))
    )
    (map-set user-profiles user
      {
        total-reports: (+ (get total-reports current-profile) reports-delta),
        total-recycled: (+ (get total-recycled current-profile) recycled-delta),
        total-earned: (+ (get total-earned current-profile) earned-delta),
        reputation-score: new-reputation,
        last-activity: current-time
      }
    )
    (ok true)
  )
)
