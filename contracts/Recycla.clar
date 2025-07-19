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
(define-constant err-center-not-registered (err u109))
(define-constant err-center-already-registered (err u110))
(define-constant err-insufficient-capacity (err u111))
(define-constant err-invalid-waste-type (err u112))
(define-constant err-collection-not-scheduled (err u113))
(define-constant err-collection-already-completed (err u114))

(define-constant base-report-reward u100)
(define-constant base-recycle-reward u200)
(define-constant verification-reward u50)
(define-constant min-verifications u3)

;; data vars
(define-data-var next-report-id uint u1)
(define-data-var total-recycled uint u0)
(define-data-var contract-balance uint u0)
(define-data-var next-center-id uint u1)
(define-data-var next-collection-id uint u1)
(define-data-var total-centers uint u0)

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

(define-map collection-centers
  uint
  {
    owner: principal,
    name: (string-ascii 100),
    location-lat: int,
    location-lng: int,
    waste-types: (list 10 (string-ascii 20)),
    max-capacity: uint,
    current-capacity: uint,
    is-active: bool,
    registration-timestamp: uint,
    total-collections: uint,
    reputation-score: uint,
    service-fee: uint
  }
)

(define-map collection-schedules
  uint
  {
    center-id: uint,
    report-id: uint,
    scheduler: principal,
    scheduled-time: uint,
    waste-type: (string-ascii 50),
    estimated-amount: uint,
    status: (string-ascii 20),
    completion-timestamp: uint,
    actual-amount: uint,
    fee-paid: uint
  }
)

(define-map center-ratings
  { center-id: uint, rater: principal }
  { rating: uint, timestamp: uint, comment: (string-ascii 200) }
)

(define-map center-operators
  uint
  (list 5 principal)
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

(define-public (register-collection-center (name (string-ascii 100)) (lat int) (lng int) (waste-types (list 10 (string-ascii 20))) (max-capacity uint) (service-fee uint))
  (let
    (
      (center-id (var-get next-center-id))
      (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    )
    (asserts! (and (>= lat -90000000) (<= lat 90000000)) err-invalid-coordinates)
    (asserts! (and (>= lng -180000000) (<= lng 180000000)) err-invalid-coordinates)
    (asserts! (> max-capacity u0) err-invalid-amount)
    (asserts! (> (len waste-types) u0) err-invalid-waste-type)
    
    (map-set collection-centers center-id
      {
        owner: tx-sender,
        name: name,
        location-lat: lat,
        location-lng: lng,
        waste-types: waste-types,
        max-capacity: max-capacity,
        current-capacity: u0,
        is-active: true,
        registration-timestamp: current-time,
        total-collections: u0,
        reputation-score: u500,
        service-fee: service-fee
      }
    )
    
    (map-set center-operators center-id (list tx-sender))
    (var-set next-center-id (+ center-id u1))
    (var-set total-centers (+ (var-get total-centers) u1))
    (ok center-id)
  )
)

(define-public (update-center-capacity (center-id uint) (new-capacity uint))
  (let
    (
      (center (unwrap! (map-get? collection-centers center-id) err-center-not-registered))
    )
    (asserts! (is-eq tx-sender (get owner center)) err-owner-only)
    (asserts! (>= new-capacity (get current-capacity center)) err-insufficient-capacity)
    
    (map-set collection-centers center-id
      (merge center { max-capacity: new-capacity })
    )
    (ok true)
  )
)

(define-public (add-waste-type-to-center (center-id uint) (waste-type (string-ascii 20)))
  (let
    (
      (center (unwrap! (map-get? collection-centers center-id) err-center-not-registered))
      (current-types (get waste-types center))
    )
    (asserts! (is-eq tx-sender (get owner center)) err-owner-only)
    (asserts! (< (len current-types) u10) err-insufficient-capacity)
    
    (map-set collection-centers center-id
      (merge center { waste-types: (unwrap! (as-max-len? (append current-types waste-type) u10) err-insufficient-capacity) })
    )
    (ok true)
  )
)

(define-public (schedule-collection (center-id uint) (report-id uint) (scheduled-time uint) (estimated-amount uint))
  (let
    (
      (center (unwrap! (map-get? collection-centers center-id) err-center-not-registered))
      (report (unwrap! (map-get? waste-reports report-id) err-not-found))
      (collection-id (var-get next-collection-id))
      (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    )
    (asserts! (get verified report) err-not-found)
    (asserts! (not (get recycled report)) err-already-verified)
    (asserts! (get is-active center) err-center-not-registered)
    (asserts! (>= (+ (get current-capacity center) estimated-amount) (get max-capacity center)) err-insufficient-capacity)
    (asserts! (> scheduled-time current-time) err-invalid-amount)
    
    (map-set collection-schedules collection-id
      {
        center-id: center-id,
        report-id: report-id,
        scheduler: tx-sender,
        scheduled-time: scheduled-time,
        waste-type: (get waste-type report),
        estimated-amount: estimated-amount,
        status: "scheduled",
        completion-timestamp: u0,
        actual-amount: u0,
        fee-paid: u0
      }
    )
    
    (map-set collection-centers center-id
      (merge center { current-capacity: (+ (get current-capacity center) estimated-amount) })
    )
    
    (var-set next-collection-id (+ collection-id u1))
    (ok collection-id)
  )
)

(define-public (complete-collection (collection-id uint) (actual-amount uint))
  (let
    (
      (collection (unwrap! (map-get? collection-schedules collection-id) err-collection-not-scheduled))
      (center (unwrap! (map-get? collection-centers (get center-id collection)) err-center-not-registered))
      (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    )
    (asserts! (is-eq tx-sender (get owner center)) err-owner-only)
    (asserts! (is-eq (get status collection) "scheduled") err-collection-already-completed)
    (asserts! (> actual-amount u0) err-invalid-amount)
    
    (let
      (
        (capacity-difference (- (get estimated-amount collection) actual-amount))
        (collection-fee (get service-fee center))
        (scheduler-balance (default-to u0 (map-get? user-balances (get scheduler collection))))
      )
      (asserts! (>= scheduler-balance collection-fee) err-insufficient-balance)
      
      (map-set collection-schedules collection-id
        (merge collection {
          status: "completed",
          completion-timestamp: current-time,
          actual-amount: actual-amount,
          fee-paid: collection-fee
        })
      )
      
      (map-set collection-centers (get center-id collection)
        (merge center {
          current-capacity: (- (get current-capacity center) capacity-difference),
          total-collections: (+ (get total-collections center) u1),
          reputation-score: (+ (get reputation-score center) u10)
        })
      )
      
      (map-set user-balances (get scheduler collection) (- scheduler-balance collection-fee))
      (map-set user-balances (get owner center) 
        (+ (default-to u0 (map-get? user-balances (get owner center))) collection-fee)
      )
      
      (try! (confirm-recycling (get report-id collection)))
      (ok true)
    )
  )
)

(define-public (rate-collection-center (center-id uint) (rating uint) (comment (string-ascii 200)))
  (let
    (
      (center (unwrap! (map-get? collection-centers center-id) err-center-not-registered))
      (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
      (rating-key { center-id: center-id, rater: tx-sender })
    )
    (asserts! (and (>= rating u1) (<= rating u5)) err-invalid-amount)
    (asserts! (not (is-eq tx-sender (get owner center))) err-cannot-verify-own)
    
    (map-set center-ratings rating-key
      { rating: rating, timestamp: current-time, comment: comment }
    )
    
    (let
      (
        (reputation-adjustment (if (>= rating u4) u5 (- u0 u5)))
      )
      (map-set collection-centers center-id
        (merge center { reputation-score: (+ (get reputation-score center) reputation-adjustment) })
      )
      (ok true)
    )
  )
)

(define-public (toggle-center-status (center-id uint))
  (let
    (
      (center (unwrap! (map-get? collection-centers center-id) err-center-not-registered))
    )
    (asserts! (is-eq tx-sender (get owner center)) err-owner-only)
    
    (map-set collection-centers center-id
      (merge center { is-active: (not (get is-active center)) })
    )
    (ok (not (get is-active center)))
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

(define-read-only (get-collection-center (center-id uint))
  (map-get? collection-centers center-id)
)

(define-read-only (get-collection-schedule (collection-id uint))
  (map-get? collection-schedules collection-id)
)

(define-read-only (get-center-rating (center-id uint) (rater principal))
  (map-get? center-ratings { center-id: center-id, rater: rater })
)

(define-read-only (get-center-operators (center-id uint))
  (map-get? center-operators center-id)
)

(define-read-only (get-centers-near-location (lat int) (lng int) (radius int))
  (var-get next-center-id)
)

(define-read-only (get-available-centers-for-waste-type (waste-type (string-ascii 20)))
  (var-get next-center-id)
)

(define-read-only (get-center-performance-stats (center-id uint))
  (let
    (
      (center (unwrap! (map-get? collection-centers center-id) none))
    )
    (some {
      total-collections: (get total-collections center),
      reputation-score: (get reputation-score center),
      capacity-utilization: (/ (* (get current-capacity center) u100) (get max-capacity center)),
      is-active: (get is-active center),
      service-fee: (get service-fee center)
    })
  )
)

(define-read-only (get-total-centers)
  (var-get total-centers)
)

(define-read-only (get-collection-stats)
  {
    total-centers: (var-get total-centers),
    next-center-id: (var-get next-center-id),
    next-collection-id: (var-get next-collection-id)
  }
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


