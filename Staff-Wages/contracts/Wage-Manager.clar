;; Enterprise Payroll Management System Smart Contract
;; Description: A comprehensive blockchain-based payroll management system for enterprises
;; Features: Employee management, automated payroll processing, tax withholding, 
;; benefits calculation, hourly/salary payment modes, and complete audit trail

;; CONSTANTS AND ERROR DEFINITIONS

;; Contract ownership
(define-constant contract-owner tx-sender)

;; Error constants
(define-constant ERR-UNAUTHORIZED-ACCESS (err u100))
(define-constant ERR-EMPLOYEE-NOT-FOUND (err u101))
(define-constant ERR-INSUFFICIENT-CONTRACT-BALANCE (err u102))
(define-constant ERR-EMPLOYEE-ALREADY-EXISTS (err u103))
(define-constant ERR-INVALID-AMOUNT-PROVIDED (err u104))
(define-constant ERR-INVALID-DATE-SPECIFIED (err u105))
(define-constant ERR-PAYMENT-ALREADY-PROCESSED (err u106))
(define-constant ERR-INVALID-PARAMETER-VALUE (err u107))
(define-constant ERR-INVALID-RATE-SPECIFIED (err u108))
(define-constant ERR-INVALID-NAME-PROVIDED (err u109))
(define-constant ERR-INVALID-ADDRESS-PROVIDED (err u110))

;; Business logic constants
(define-constant maximum-tax-rate u10000) ;; 100% in basis points
(define-constant maximum-benefits-rate u10000) ;; 100% in basis points
(define-constant maximum-annual-salary u1000000000000) ;; Upper salary limit
(define-constant maximum-hourly-rate u1000000) ;; Upper hourly rate limit
(define-constant maximum-hours-per-period u1000) ;; Max hours per pay period
(define-constant basis-points-divisor u10000) ;; For percentage calculations
(define-constant default-pay-period-duration u1209600) ;; 14 days in seconds
(define-constant maximum-pay-period-duration u2592000) ;; 30 days in seconds

;; DATA STRUCTURES AND STORAGE

;; Primary employee registry
(define-map employee-registry 
  { employee-identifier: (string-ascii 36) } 
  {
    wallet-address: principal,
    full-name: (string-ascii 50),
    annual-salary: uint,
    hourly-compensation-rate: uint,
    is-hourly-employee: bool,
    benefits-percentage: uint,
    tax-withholding-percentage: uint,
    last-payment-timestamp: uint,
    employment-status: bool
  }
)

;; Payment history and audit trail
(define-map payment-history-ledger
  { 
    employee-identifier: (string-ascii 36),
    pay-period-end-date: uint
  }
  {
    gross-payment-amount: uint,
    tax-withholding-amount: uint,
    benefits-deduction-amount: uint,
    net-payment-amount: uint,
    payment-processed-timestamp: uint,
    payment-completion-status: bool
  }
)

;; Hours tracking for hourly employees
(define-map employee-hours-log
  {
    employee-identifier: (string-ascii 36),
    pay-period-end-date: uint
  }
  { hours-worked-count: uint }
)

;; Employee indexing system for iteration
(define-map employee-directory-index
  { directory-position: uint }
  { employee-identifier: (string-ascii 36) }
)

;; CONTRACT STATE VARIABLES

(define-data-var total-contract-balance uint u0)
(define-data-var next-scheduled-payday uint u0)
(define-data-var current-pay-period-length uint default-pay-period-duration)
(define-data-var total-employee-count uint u0)
(define-data-var maximum-allowed-pay-period uint maximum-pay-period-duration)

;; UTILITY AND VALIDATION FUNCTIONS

;; Validate principal address is legitimate
(define-read-only (is-valid-wallet-address (wallet-address principal))
  (not (is-eq wallet-address 'SP000000000000000000002Q6VF78)))

;; Validate percentage rates are within bounds
(define-read-only (is-valid-percentage-rate (rate-value uint))
  (<= rate-value maximum-tax-rate))

;; Validate future date for pay periods
(define-read-only (is-valid-future-date (target-date uint))
  (let ((current-blockchain-time (default-to u0 (get-block-info? time block-height))))
    (> target-date current-blockchain-time)))

;; Check if employee record exists
(define-read-only (employee-record-exists (employee-identifier (string-ascii 36)))
  (is-some (map-get? employee-registry { employee-identifier: employee-identifier })))

;; Validate employee is currently active
(define-read-only (is-employee-currently-active (employee-identifier (string-ascii 36)))
  (match (map-get? employee-registry { employee-identifier: employee-identifier })
    employee-record (get employment-status employee-record)
    false
  )
)

;; EMPLOYEE INFORMATION RETRIEVAL FUNCTIONS

;; Retrieve complete employee profile
(define-read-only (get-employee-profile (employee-identifier (string-ascii 36)))
  (map-get? employee-registry { employee-identifier: employee-identifier })
)

;; Get employee payment history for specific period
(define-read-only (get-employee-payment-record (employee-identifier (string-ascii 36)) (pay-period-end-date uint))
  (map-get? payment-history-ledger { employee-identifier: employee-identifier, pay-period-end-date: pay-period-end-date })
)

;; Retrieve hours worked for specific pay period
(define-read-only (get-employee-hours-worked (employee-identifier (string-ascii 36)) (pay-period-end-date uint))
  (default-to { hours-worked-count: u0 }
    (map-get? employee-hours-log { employee-identifier: employee-identifier, pay-period-end-date: pay-period-end-date })
  )
)

;; Get employee by directory position
(define-read-only (get-employee-by-directory-position (directory-position uint))
  (match (map-get? employee-directory-index { directory-position: directory-position })
    directory-entry (some (get employee-identifier directory-entry))
    none
  )
)

;; CONTRACT STATUS AND CONFIGURATION FUNCTIONS

;; Get current contract balance
(define-read-only (get-current-contract-balance)
  (var-get total-contract-balance)
)

;; Get next scheduled payment date
(define-read-only (get-next-scheduled-payment-date)
  (var-get next-scheduled-payday)
)

;; Get current pay period configuration
(define-read-only (get-current-pay-period-duration)
  (var-get current-pay-period-length)
)

;; Get total number of employees
(define-read-only (get-total-employee-count)
  (var-get total-employee-count)
)

;; PAYMENT CALCULATION ENGINE

;; Calculate comprehensive payment breakdown for employee
(define-read-only (calculate-employee-payment-breakdown (employee-identifier (string-ascii 36)) (pay-period-end-date uint))
  (match (map-get? employee-registry { employee-identifier: employee-identifier })
    employee-record 
      (let (
        (recorded-hours (get hours-worked-count (get-employee-hours-worked employee-identifier pay-period-end-date)))
        (calculated-gross-amount (if (get is-hourly-employee employee-record)
                                   (* (get hourly-compensation-rate employee-record) recorded-hours)
                                   (get annual-salary employee-record)))
        (calculated-tax-withholding (/ (* calculated-gross-amount (get tax-withholding-percentage employee-record)) basis-points-divisor))
        (calculated-benefits-deduction (/ (* calculated-gross-amount (get benefits-percentage employee-record)) basis-points-divisor))
        (calculated-net-payment (- (- calculated-gross-amount calculated-tax-withholding) calculated-benefits-deduction))
      )
      (ok {
        gross-payment-amount: calculated-gross-amount,
        tax-withholding-amount: calculated-tax-withholding,
        benefits-deduction-amount: calculated-benefits-deduction,
        net-payment-amount: calculated-net-payment
      }))
    ERR-EMPLOYEE-NOT-FOUND
  )
)

;; CONTRACT FUNDING MANAGEMENT

;; Add funds to contract balance
(define-public (deposit-contract-funds (deposit-amount uint))
  (begin
    (asserts! (> deposit-amount u0) ERR-INVALID-AMOUNT-PROVIDED)
    (var-set total-contract-balance (+ (var-get total-contract-balance) deposit-amount))
    (ok deposit-amount)
  )
)

;; Withdraw funds from contract (owner only)
(define-public (withdraw-contract-funds (withdrawal-amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (> withdrawal-amount u0) ERR-INVALID-AMOUNT-PROVIDED)
    (asserts! (<= withdrawal-amount (var-get total-contract-balance)) ERR-INSUFFICIENT-CONTRACT-BALANCE)
    (var-set total-contract-balance (- (var-get total-contract-balance) withdrawal-amount))
    (ok withdrawal-amount)
  )
)

;; EMPLOYEE LIFECYCLE MANAGEMENT

;; Register new employee in the system
(define-public (register-new-employee 
  (employee-identifier (string-ascii 36))
  (employee-wallet-address principal)
  (employee-full-name (string-ascii 50))
  (employee-annual-salary uint)
  (employee-hourly-rate uint)
  (is-hourly-position bool)
  (benefits-rate-percentage uint)
  (tax-withholding-rate-percentage uint)
)
  (begin
    ;; Authorization verification
    (asserts! (is-eq tx-sender contract-owner) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Input validation checks
    (asserts! (not (employee-record-exists employee-identifier)) ERR-EMPLOYEE-ALREADY-EXISTS)
    (asserts! (is-valid-wallet-address employee-wallet-address) ERR-INVALID-ADDRESS-PROVIDED)
    (asserts! (> (len employee-full-name) u0) ERR-INVALID-NAME-PROVIDED)
    (asserts! (is-valid-percentage-rate benefits-rate-percentage) ERR-INVALID-RATE-SPECIFIED)
    (asserts! (is-valid-percentage-rate tax-withholding-rate-percentage) ERR-INVALID-RATE-SPECIFIED)
    
    ;; Validate compensation structure based on employment type
    (asserts! (or (and is-hourly-position 
                       (> employee-hourly-rate u0) 
                       (<= employee-hourly-rate maximum-hourly-rate)
                       (is-eq employee-annual-salary u0))
                 (and (not is-hourly-position) 
                      (> employee-annual-salary u0) 
                      (<= employee-annual-salary maximum-annual-salary)
                      (is-eq employee-hourly-rate u0)))
             ERR-INVALID-AMOUNT-PROVIDED)
    
    ;; Create employee record
    (map-set employee-registry
      { employee-identifier: employee-identifier }
      {
        wallet-address: employee-wallet-address,
        full-name: employee-full-name,
        annual-salary: employee-annual-salary,
        hourly-compensation-rate: employee-hourly-rate,
        is-hourly-employee: is-hourly-position,
        benefits-percentage: benefits-rate-percentage,
        tax-withholding-percentage: tax-withholding-rate-percentage,
        last-payment-timestamp: u0,
        employment-status: true
      }
    )
    
    ;; Update employee directory index
    (let ((current-employee-count (var-get total-employee-count)))
      (map-set employee-directory-index 
        { directory-position: current-employee-count }
        { employee-identifier: employee-identifier }
      )
      (var-set total-employee-count (+ current-employee-count u1))
    )
    
    (ok true)
  )
)

;; Update existing employee information
(define-public (update-employee-information 
  (employee-identifier (string-ascii 36))
  (updated-wallet-address principal)
  (updated-full-name (string-ascii 50))
  (updated-annual-salary uint)
  (updated-hourly-rate uint)
  (updated-hourly-status bool)
  (updated-benefits-rate uint)
  (updated-tax-rate uint)
)
  (begin
    ;; Authorization verification
    (asserts! (is-eq tx-sender contract-owner) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Validate employee exists
    (asserts! (employee-record-exists employee-identifier) ERR-EMPLOYEE-NOT-FOUND)
    (asserts! (is-valid-wallet-address updated-wallet-address) ERR-INVALID-ADDRESS-PROVIDED)
    (asserts! (> (len updated-full-name) u0) ERR-INVALID-NAME-PROVIDED)
    (asserts! (is-valid-percentage-rate updated-benefits-rate) ERR-INVALID-RATE-SPECIFIED)
    (asserts! (is-valid-percentage-rate updated-tax-rate) ERR-INVALID-RATE-SPECIFIED)
    
    ;; Validate compensation structure
    (asserts! (or (and updated-hourly-status 
                       (> updated-hourly-rate u0) 
                       (<= updated-hourly-rate maximum-hourly-rate)
                       (is-eq updated-annual-salary u0))
                 (and (not updated-hourly-status) 
                      (> updated-annual-salary u0) 
                      (<= updated-annual-salary maximum-annual-salary)
                      (is-eq updated-hourly-rate u0)))
             ERR-INVALID-AMOUNT-PROVIDED)
    
    (let ((existing-employee-record (unwrap! (map-get? employee-registry { employee-identifier: employee-identifier }) ERR-EMPLOYEE-NOT-FOUND)))
      (map-set employee-registry
        { employee-identifier: employee-identifier }
        {
          wallet-address: updated-wallet-address,
          full-name: updated-full-name,
          annual-salary: updated-annual-salary,
          hourly-compensation-rate: updated-hourly-rate,
          is-hourly-employee: updated-hourly-status,
          benefits-percentage: updated-benefits-rate,
          tax-withholding-percentage: updated-tax-rate,
          last-payment-timestamp: (get last-payment-timestamp existing-employee-record),
          employment-status: (get employment-status existing-employee-record)
        }
      )
    )
    (ok true)
  )
)

;; Suspend employee (maintain record but mark inactive)
(define-public (suspend-employee-account (employee-identifier (string-ascii 36)))
  (begin
    (asserts! (is-eq tx-sender contract-owner) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (employee-record-exists employee-identifier) ERR-EMPLOYEE-NOT-FOUND)
    
    (let ((existing-employee-record (unwrap! (map-get? employee-registry { employee-identifier: employee-identifier }) ERR-EMPLOYEE-NOT-FOUND)))
      (map-set employee-registry
        { employee-identifier: employee-identifier }
        {
          wallet-address: (get wallet-address existing-employee-record),
          full-name: (get full-name existing-employee-record),
          annual-salary: (get annual-salary existing-employee-record),
          hourly-compensation-rate: (get hourly-compensation-rate existing-employee-record),
          is-hourly-employee: (get is-hourly-employee existing-employee-record),
          benefits-percentage: (get benefits-percentage existing-employee-record),
          tax-withholding-percentage: (get tax-withholding-percentage existing-employee-record),
          last-payment-timestamp: (get last-payment-timestamp existing-employee-record),
          employment-status: false
        }
      )
    )
    (ok true)
  )
)

;; Reactivate suspended employee
(define-public (reactivate-employee-account (employee-identifier (string-ascii 36)))
  (begin
    (asserts! (is-eq tx-sender contract-owner) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (employee-record-exists employee-identifier) ERR-EMPLOYEE-NOT-FOUND)
    
    (let ((existing-employee-record (unwrap! (map-get? employee-registry { employee-identifier: employee-identifier }) ERR-EMPLOYEE-NOT-FOUND)))
      (map-set employee-registry
        { employee-identifier: employee-identifier }
        {
          wallet-address: (get wallet-address existing-employee-record),
          full-name: (get full-name existing-employee-record),
          annual-salary: (get annual-salary existing-employee-record),
          hourly-compensation-rate: (get hourly-compensation-rate existing-employee-record),
          is-hourly-employee: (get is-hourly-employee existing-employee-record),
          benefits-percentage: (get benefits-percentage existing-employee-record),
          tax-withholding-percentage: (get tax-withholding-percentage existing-employee-record),
          last-payment-timestamp: (get last-payment-timestamp existing-employee-record),
          employment-status: true
        }
      )
    )
    (ok true)
  )
)

;; TIME TRACKING AND HOURS MANAGEMENT

;; Record work hours for hourly employees
(define-public (log-employee-work-hours (employee-identifier (string-ascii 36)) (pay-period-end-date uint) (total-hours-worked uint))
  (begin
    ;; Authorization verification
    (asserts! (is-eq tx-sender contract-owner) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Input validation
    (asserts! (employee-record-exists employee-identifier) ERR-EMPLOYEE-NOT-FOUND)
    (asserts! (and (> total-hours-worked u0) (<= total-hours-worked maximum-hours-per-period)) ERR-INVALID-AMOUNT-PROVIDED)
    (asserts! (is-valid-future-date pay-period-end-date) ERR-INVALID-DATE-SPECIFIED)
    
    (let ((employee-record (unwrap! (map-get? employee-registry { employee-identifier: employee-identifier }) ERR-EMPLOYEE-NOT-FOUND)))
      (asserts! (get is-hourly-employee employee-record) ERR-UNAUTHORIZED-ACCESS)
      
      ;; Store hours worked data
      (map-set employee-hours-log
        { employee-identifier: employee-identifier, pay-period-end-date: pay-period-end-date }
        { hours-worked-count: total-hours-worked }
      )
    )
    (ok true)
  )
)

;; PAYROLL PROCESSING ENGINE

;; Process individual employee payment
(define-public (process-individual-employee-payment (employee-identifier (string-ascii 36)) (pay-period-end-date uint))
  (begin
    ;; Authorization verification
    (asserts! (is-eq tx-sender contract-owner) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Input validation
    (asserts! (employee-record-exists employee-identifier) ERR-EMPLOYEE-NOT-FOUND)
    (asserts! (is-valid-future-date pay-period-end-date) ERR-INVALID-DATE-SPECIFIED)
    
    ;; Verify payment hasn't been processed already
    (asserts! (is-none (map-get? payment-history-ledger 
                                { employee-identifier: employee-identifier, pay-period-end-date: pay-period-end-date }))
             ERR-PAYMENT-ALREADY-PROCESSED)
    
    (let (
      (employee-record (unwrap-panic (map-get? employee-registry { employee-identifier: employee-identifier })))
    )
      ;; Calculate payment breakdown
      (try! (calculate-employee-payment-breakdown employee-identifier pay-period-end-date))
      
      ;; Extract payment calculation results
      (let (
        (payment-calculation (unwrap-panic (calculate-employee-payment-breakdown employee-identifier pay-period-end-date)))
        (gross-amount (get gross-payment-amount payment-calculation))
        (tax-withholding (get tax-withholding-amount payment-calculation))
        (benefits-deduction (get benefits-deduction-amount payment-calculation))
        (net-payment (get net-payment-amount payment-calculation))
        (current-blockchain-time (unwrap-panic (get-block-info? time block-height)))
      )
        ;; Verify employee is active
        (asserts! (get employment-status employee-record) ERR-UNAUTHORIZED-ACCESS)
        
        ;; Verify sufficient contract balance
        (asserts! (>= (var-get total-contract-balance) net-payment) ERR-INSUFFICIENT-CONTRACT-BALANCE)
        
        ;; Record payment in history ledger
        (map-set payment-history-ledger
          { employee-identifier: employee-identifier, pay-period-end-date: pay-period-end-date }
          {
            gross-payment-amount: gross-amount,
            tax-withholding-amount: tax-withholding,
            benefits-deduction-amount: benefits-deduction,
            net-payment-amount: net-payment,
            payment-processed-timestamp: current-blockchain-time,
            payment-completion-status: true
          }
        )
        
        ;; Update employee's payment timestamp
        (map-set employee-registry
          { employee-identifier: employee-identifier }
          {
            wallet-address: (get wallet-address employee-record),
            full-name: (get full-name employee-record),
            annual-salary: (get annual-salary employee-record),
            hourly-compensation-rate: (get hourly-compensation-rate employee-record),
            is-hourly-employee: (get is-hourly-employee employee-record),
            benefits-percentage: (get benefits-percentage employee-record),
            tax-withholding-percentage: (get tax-withholding-percentage employee-record),
            last-payment-timestamp: current-blockchain-time,
            employment-status: (get employment-status employee-record)
          }
        )
        
        ;; Deduct payment from contract balance
        (var-set total-contract-balance (- (var-get total-contract-balance) net-payment))
        
        (ok net-payment)
      )
    )
  )
)

;; PAYROLL BATCH PROCESSING AND SCHEDULING

;; Execute complete payroll run for pay period
(define-public (execute-payroll-batch-processing (pay-period-end-date uint))
  (begin
    ;; Authorization verification
    (asserts! (is-eq tx-sender contract-owner) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Input validation
    (asserts! (is-valid-future-date pay-period-end-date) ERR-INVALID-DATE-SPECIFIED)
    
    (let (
      (current-blockchain-time (unwrap-panic (get-block-info? time block-height)))
      (validated-period-end pay-period-end-date)
      (validated-pay-period-duration (var-get current-pay-period-length))
    )
      ;; Schedule next payroll date
      (var-set next-scheduled-payday (+ validated-period-end validated-pay-period-duration))
      
      ;; Note: Batch processing requires external coordination
      ;; Due to Clarity limitations, individual payments must be processed separately
      ;; This function sets up the payroll period and schedules the next run
      
      (ok true)
    )
  )
)

;; PAYROLL CONFIGURATION MANAGEMENT

;; Configure pay period duration
(define-public (configure-pay-period-duration (new-duration-seconds uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (and (> new-duration-seconds u0) (<= new-duration-seconds (var-get maximum-allowed-pay-period))) ERR-INVALID-AMOUNT-PROVIDED)
    (var-set current-pay-period-length new-duration-seconds)
    (ok true)
  )
)

;; Initialize payroll system with first payment date
(define-public (initialize-payroll-system (initial-payday-date uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (is-eq (var-get next-scheduled-payday) u0) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (is-valid-future-date initial-payday-date) ERR-INVALID-DATE-SPECIFIED)
    
    ;; Set initial payday with validated input
    (var-set next-scheduled-payday initial-payday-date)
    (ok true)
  )
)