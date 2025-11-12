;; VaultChain: Enterprise Real-World Asset Tokenization Protocol
;;
;; A next-generation institutional-grade protocol for tokenizing and managing
;; real-world assets on Bitcoin's most secure Layer 2 network - Stacks.
;; 
;; VaultChain transforms traditional asset ownership through Bitcoin's proven
;; security model, enabling fractional ownership of high-value assets with
;; enterprise-level compliance and regulatory adherence built into every
;; transaction.
;;
;; Key Value Propositions:
;; - Bitcoin-Secured Ownership: Every asset is anchored to Bitcoin's immutable ledger
;; - Institutional Compliance: Built-in KYC/AML with granular regulatory controls  
;; - Fractional Liquidity: Transform illiquid assets into tradeable digital shares
;; - Transparent Provenance: Immutable ownership history with block-level verification
;; - Enterprise Security: Multi-layered protection leveraging Bitcoin's hash power
;;
;; Perfect for: Real Estate, Fine Art, Commodities, Private Equity, Luxury Assets
;;
;; Built on Stacks - Where Bitcoin Meets DeFi Innovation

;; Contract Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant CONTRACT-ADMIN CONTRACT-OWNER)

;; Error Codes
(define-constant ERR-UNAUTHORIZED (err u1))
(define-constant ERR-INSUFFICIENT-FUNDS (err u2))
(define-constant ERR-INVALID-ASSET (err u3))
(define-constant ERR-TRANSFER-FAILED (err u4))
(define-constant ERR-COMPLIANCE-CHECK-FAILED (err u5))
(define-constant ERR-INVALID-INPUT (err u6))
(define-constant ERR-INSUFFICIENT-SHARES (err u7))
(define-constant ERR-EVENT-LOGGING (err u8))

;; STATE MANAGEMENT

;; Global State Variables
(define-data-var next-asset-id uint u1)
(define-data-var last-event-id uint u0)

;; Asset Registry - Core asset metadata and ownership structure
(define-map asset-registry 
  {asset-id: uint} 
  {
    owner: principal,
    total-supply: uint,
    fractional-shares: uint,
    metadata-uri: (string-utf8 256),
    is-transferable: bool,
    created-at: uint
  }
)

;; Compliance Management - KYC/AML status tracking
(define-map compliance-status 
  {asset-id: uint, user: principal} 
  {
    is-approved: bool,
    last-updated: uint,
    approved-by: principal
  }
)

;; Share Ownership Tracking - Fractional ownership balances
(define-map share-ownership
  {asset-id: uint, owner: principal}
  {shares: uint}
)

;; Event Logging - Immutable transaction history
(define-map events
  {event-id: uint}
  {
    event-type: (string-utf8 24),
    asset-id: uint,
    principal1: principal,
    timestamp: uint
  }
)

;; NFT DEFINITION

;; Primary ownership token for tokenized assets
(define-non-fungible-token asset-ownership-token uint)

;; PRIVATE UTILITY FUNCTIONS

;; Event Logging System
(define-private (log-event 
  (event-type (string-utf8 24))
  (asset-id uint)
  (principal1 principal)
) 
  (begin
    (let ((event-id (+ (var-get last-event-id) u1)))
      (map-set events
        {event-id: event-id}
        {
          event-type: event-type,
          asset-id: asset-id,
          principal1: principal1,
          timestamp: stacks-block-height
        }
      )
      (var-set last-event-id event-id)
      (ok event-id)
    )
  )
)

;; Input Validation Functions
(define-private (is-valid-metadata-uri (uri (string-utf8 256)))
  (and 
    (> (len uri) u5)
    (<= (len uri) u256)
  )
)

(define-private (is-valid-asset-id (asset-id uint))
  (and
    (> asset-id u0)
    (< asset-id (var-get next-asset-id))
  )
)

(define-private (is-valid-principal (user principal))
  (and
    (not (is-eq user CONTRACT-OWNER))
    (not (is-eq user (as-contract tx-sender)))
  )
)

;; Compliance Verification
(define-private (is-compliance-check-passed 
  (asset-id uint) 
  (user principal)
) 
  (match (map-get? compliance-status {asset-id: asset-id, user: user})
    compliance-data (get is-approved compliance-data)
    false
  )
)

;; Share Management Utilities
(define-private (get-shares (asset-id uint) (owner principal))
  (default-to u0 
    (get shares 
      (map-get? share-ownership {asset-id: asset-id, owner: owner})
    )
  )
)

(define-private (set-shares (asset-id uint) (owner principal) (amount uint))
  (map-set share-ownership 
    {asset-id: asset-id, owner: owner}
    {shares: amount}
  )
)

;; PUBLIC FUNCTIONS - CORE PROTOCOL OPERATIONS

;; Asset Tokenization - Convert real-world assets into blockchain tokens
(define-public (create-asset 
  (total-supply uint) 
  (fractional-shares uint)
  (metadata-uri (string-utf8 256))
)
  (begin 
    ;; Input validation
    (asserts! (> total-supply u0) ERR-INVALID-INPUT)
    (asserts! (> fractional-shares u0) ERR-INVALID-INPUT)
    (asserts! (<= fractional-shares total-supply) ERR-INVALID-INPUT)
    (asserts! (is-valid-metadata-uri metadata-uri) ERR-INVALID-INPUT)
    
    (let ((asset-id (var-get next-asset-id)))
      ;; Register asset in protocol
      (map-set asset-registry 
        {asset-id: asset-id}
        {
          owner: tx-sender,
          total-supply: total-supply,
          fractional-shares: fractional-shares,
          metadata-uri: metadata-uri,
          is-transferable: true,
          created-at: stacks-block-height
        }
      )
      
      ;; Initialize ownership structure
      (set-shares asset-id tx-sender total-supply)
      
      ;; Mint primary ownership NFT
      (unwrap! (nft-mint? asset-ownership-token asset-id tx-sender) ERR-TRANSFER-FAILED)
      
      ;; Log creation event
      (unwrap! (log-event u"ASSET_CREATED" asset-id tx-sender) ERR-EVENT-LOGGING)
      
      ;; Update global state
      (var-set next-asset-id (+ asset-id u1))
      (ok asset-id)
    )
  )
)

;; Fractional Ownership Transfer - Enable partial asset trading
(define-public (transfer-fractional-ownership 
  (asset-id uint) 
  (to-principal principal) 
  (amount uint)
)
  (let (
    (asset (unwrap! (map-get? asset-registry {asset-id: asset-id}) ERR-INVALID-ASSET))
    (sender tx-sender)
    (sender-shares (get-shares asset-id sender))
  )
    ;; Comprehensive validation
    (asserts! (is-valid-asset-id asset-id) ERR-INVALID-INPUT)
    (asserts! (is-valid-principal to-principal) ERR-INVALID-INPUT)
    (asserts! (get is-transferable asset) ERR-UNAUTHORIZED)
    (asserts! (is-compliance-check-passed asset-id to-principal) ERR-COMPLIANCE-CHECK-FAILED)
    (asserts! (>= sender-shares amount) ERR-INSUFFICIENT-SHARES)
    
    ;; Execute share transfer
    (set-shares asset-id sender (- sender-shares amount))
    (set-shares asset-id to-principal (+ (get-shares asset-id to-principal) amount))
    
    ;; Log transfer event
    (unwrap! (log-event u"TRANSFER" asset-id sender) ERR-EVENT-LOGGING)
    
    ;; Handle primary NFT ownership transfer if full ownership transferred
    (if (is-eq sender-shares amount)
      (unwrap! (nft-transfer? asset-ownership-token asset-id sender to-principal) ERR-TRANSFER-FAILED)
      true
    )
    
    (ok true)
  )
)

;; Compliance Management - Set KYC/AML approval status
(define-public (set-compliance-status 
  (asset-id uint) 
  (user principal) 
  (is-approved bool)
)
  (begin
    ;; Authorization check
    (asserts! (is-valid-asset-id asset-id) ERR-INVALID-INPUT)
    (asserts! (is-valid-principal user) ERR-INVALID-INPUT)
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    
    ;; Update compliance status
    (map-set compliance-status 
      {asset-id: asset-id, user: user} 
      {
        is-approved: is-approved,
        last-updated: stacks-block-height,
        approved-by: tx-sender
      }
    )
    
    ;; Log compliance event
    (unwrap! (log-event u"COMPLIANCE_UPDATE" asset-id user) ERR-EVENT-LOGGING)
    
    (ok is-approved)
  )
)

;; READ-ONLY FUNCTIONS - DATA ACCESS LAYER

;; Asset Information Retrieval
(define-read-only (get-asset-details (asset-id uint))
  (map-get? asset-registry {asset-id: asset-id})
)

;; Ownership Share Query
(define-read-only (get-owner-shares (asset-id uint) (owner principal))
  (ok (get-shares asset-id owner))
)

;; Compliance Status Check
(define-read-only (get-compliance-details (asset-id uint) (user principal))
  (map-get? compliance-status {asset-id: asset-id, user: user})
)

;; Event History Access
(define-read-only (get-event (event-id uint))
  (map-get? events {event-id: event-id})
)