import UIKit
import Lottie
import WordPressShared
import WordPressUI
import WordPressKit

class LoginPrologueViewController: LoginViewController {

    private var buttonViewController: NUXButtonViewController?
    var showCancel = false

    // Called when login button is tapped
    var onLoginButtonTapped: (() -> Void)?

    private let configuration = WordPressAuthenticator.shared.configuration
    private let style = WordPressAuthenticator.shared.style

    @available(iOS 13, *)
    private lazy var storedCredentialsAuthenticator = StoredCredentialsAuthenticator()
    
    @IBOutlet private weak var topContainerView: UIView!
    
    /// We can't rely on `isMovingToParent` to know if we need to track the `.prologue` step
    /// because for the root view in an App, it's always `false`.  We're relying this variiable
    /// instead, since the `.prologue` step only needs to be tracked once.
    ///
    private var prologueFlowTracked = false

    // MARK: - Lifecycle Methods

    override func viewDidLoad() {
        super.viewDidLoad()

        if let topContainerChildViewController = style.prologueTopContainerChildViewController() {
            topContainerView.subviews.forEach { $0.removeFromSuperview() }
            addChild(topContainerChildViewController)
            topContainerView.addSubview(topContainerChildViewController.view)
            topContainerChildViewController.didMove(toParent: self)

            topContainerChildViewController.view.translatesAutoresizingMaskIntoConstraints = false
            topContainerView.pinSubviewToAllEdges(topContainerChildViewController.view)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        configureButtonVC()
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        tracker.set(flow: .prologue)
        
        if !prologueFlowTracked {
            tracker.track(step: .prologue)
            prologueFlowTracked = true
        } else {
            tracker.set(step: .prologue)
        }
        
        WordPressAuthenticator.track(.loginPrologueViewed)
        
        showiCloudKeychainLoginFlow()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        self.navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.isPad() ? .all : .portrait
    }
    
    // MARK: - iCloud Keychain Login
    
    /// Starts the iCloud Keychain login flow if the conditions are given.
    ///
    private func showiCloudKeychainLoginFlow() {
        guard #available(iOS 13, *),
            WordPressAuthenticator.shared.configuration.enableUnifiedKeychainLogin,
            let navigationController = navigationController else {
                return
        }

        storedCredentialsAuthenticator.showPicker(from: navigationController)
    }

    // MARK: - Segue

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)

        if let vc = segue.destination as? NUXButtonViewController {
            buttonViewController = vc
        }
    }

    private func configureButtonVC() {
        guard let buttonViewController = buttonViewController else {
            return
        }

        guard configuration.enableUnifiedWordPress else {
            buildPrologueButtons(buttonViewController)
            return
        }

        buildUnifiedPrologueButtons(buttonViewController)
    }

    /// Displays the old UI prologue buttons.
    ///
    private func buildPrologueButtons(_ buttonViewController: NUXButtonViewController) {
        let loginTitle = NSLocalizedString("Log In", comment: "Button title.  Tapping takes the user to the login form.")
        let createTitle = NSLocalizedString("Sign up for WordPress.com", comment: "Button title. Tapping begins the process of creating a WordPress.com account.")

        buttonViewController.setupTopButton(title: loginTitle, isPrimary: false, accessibilityIdentifier: "Prologue Log In Button") { [weak self] in
            self?.onLoginButtonTapped?()
            self?.loginTapped()
        }

        if configuration.enableSignUp {
            buttonViewController.setupBottomButton(title: createTitle, isPrimary: true, accessibilityIdentifier: "Prologue Signup Button") { [weak self] in
                self?.signupTapped()
            }
        }

        if showCancel {
            let cancelTitle = NSLocalizedString("Cancel", comment: "Button title. Tapping it cancels the login flow.")
            buttonViewController.setupTertiaryButton(title: cancelTitle, isPrimary: false) { [weak self] in
                self?.dismiss(animated: true, completion: nil)
            }
        }

        buttonViewController.backgroundColor = style.buttonViewBackgroundColor
    }

    /// Displays the Unified prologue buttons.
    ///
    private func buildUnifiedPrologueButtons(_ buttonViewController: NUXButtonViewController) {
        let loginTitle = NSLocalizedString("Continue with WordPress.com",
                                           comment: "Button title. Takes the user to the login by email flow.")
        let siteAddressTitle = NSLocalizedString("Enter your site address",
                                                 comment: "Button title. Takes the user to the login by site address flow.")

        buttonViewController.setupTopButton(title: loginTitle, isPrimary: true, accessibilityIdentifier: "Prologue Log In Button") { [weak self] in
            guard let self = self else {
                return
            }
            
            self.tracker.set(flow: .wpCom)
            self.tracker.track(click: .continueWithWordPressCom)
            self.continueWithDotCom()
        }

        if configuration.enableUnifiedSiteAddress {
            buttonViewController.setupBottomButton(title: siteAddressTitle, isPrimary: false, accessibilityIdentifier: "Self Hosted Login Button") { [weak self] in
                self?.siteAddressTapped()
            }
        }

        if showCancel {
            let cancelTitle = NSLocalizedString("Cancel", comment: "Button title. Tapping it cancels the login flow.")
            buttonViewController.setupTertiaryButton(title: cancelTitle, isPrimary: false) { [weak self] in
                self?.dismiss(animated: true, completion: nil)
            }
        }

        buttonViewController.backgroundColor = style.buttonViewBackgroundColor
    }

    // MARK: - Actions

    /// Old UI. "Log In" button action.
    ///
    private func loginTapped() {
        tracker.set(source: .default)

        guard let vc = LoginPrologueLoginMethodViewController.instantiate(from: .login) else {
            DDLogError("Failed to navigate to LoginPrologueLoginMethodViewController from LoginPrologueViewController")
            return
        }

        vc.transitioningDelegate = self

        // Continue with WordPress.com button action
        vc.emailTapped = { [weak self] in
            guard let self = self else {
                return
            }

            self.presentLoginEmailView()
        }

        // Continue with Google button action
        vc.googleTapped = { [weak self] in
            self?.googleTapped()
        }

        // Site address text link button action
        vc.selfHostedTapped = { [weak self] in
            self?.loginToSelfHostedSite()
        }

        // Sign In With Apple (SIWA) button action
        vc.appleTapped = { [weak self] in
            self?.appleTapped()
        }

        vc.modalPresentationStyle = .custom
        navigationController?.present(vc, animated: true, completion: nil)
    }

    /// Old UI. "Sign up with WordPress.com" button action.
    ///
    private func signupTapped() {
        tracker.set(source: .default)
        
        // This stat is part of a funnel that provides critical information.
        // Before making ANY modification to this stat please refer to: p4qSXL-35X-p2
        WordPressAuthenticator.track(.signupButtonTapped)

        guard let vc = LoginPrologueSignupMethodViewController.instantiate(from: .login) else {
            DDLogError("Failed to navigate to LoginPrologueSignupMethodViewController")
            return
        }

        vc.loginFields = self.loginFields
        vc.dismissBlock = dismissBlock
        vc.transitioningDelegate = self
        vc.modalPresentationStyle = .custom

        vc.emailTapped = { [weak self] in
            guard let self = self else {
                return
            }

            guard self.configuration.enableUnifiedWordPress else {
                self.presentSignUpEmailView()
                return
            }

            self.presentUnifiedSignupView()
        }

        vc.googleTapped = { [weak self] in
            guard let self = self else {
                return
            }
            
            guard self.configuration.enableUnifiedGoogle else {
                self.presentGoogleSignupView()
                return
            }

            self.presentUnifiedGoogleView()
        }

        vc.appleTapped = { [weak self] in
            self?.appleTapped()
        }

        navigationController?.present(vc, animated: true, completion: nil)
    }

    private func appleTapped() {
        AppleAuthenticator.sharedInstance.delegate = self
        AppleAuthenticator.sharedInstance.showFrom(viewController: self)
    }

    private func googleTapped() {
        guard configuration.enableUnifiedGoogle else {
            GoogleAuthenticator.sharedInstance.loginDelegate = self
            GoogleAuthenticator.sharedInstance.showFrom(viewController: self, loginFields: loginFields, for: .login)
            return
        }
        
        presentUnifiedGoogleView()
    }

    /// Unified "Continue with WordPress.com" prologue button action.
    ///
    private func continueWithDotCom() {
        guard let vc = GetStartedViewController.instantiate(from: .getStarted) else {
            DDLogError("Failed to navigate from LoginPrologueViewController to GetStartedViewController")
            return
        }

        navigationController?.pushViewController(vc, animated: true)
    }

    /// Unified "Enter your site address" prologue button action.
    ///
    private func siteAddressTapped() {
        tracker.set(flow: .loginWithSiteAddress)
        tracker.track(click: .loginWithSiteAddress)

        loginToSelfHostedSite()
    }

    private func presentSignUpEmailView() {
        guard let toVC = SignupEmailViewController.instantiate(from: .signup) else {
            DDLogError("Failed to navigate to SignupEmailViewController")
            return
        }

        navigationController?.pushViewController(toVC, animated: true)
    }

    private func presentUnifiedSignupView() {
        guard let toVC = UnifiedSignupViewController.instantiate(from: .unifiedSignup) else {
            DDLogError("Failed to navigate to UnifiedSignupViewController")
            return
        }

        navigationController?.pushViewController(toVC, animated: true)
    }

    private func presentLoginEmailView() {
        guard let toVC = LoginEmailViewController.instantiate(from: .login) else {
            DDLogError("Failed to navigate to LoginEmailVC from LoginPrologueVC")
            return
        }

        navigationController?.pushViewController(toVC, animated: true)
    }

    private func presentGetStartedView() {
        guard let toVC = GetStartedViewController.instantiate(from: .getStarted) else {
            DDLogError("Failed to navigate to GetStartedViewController")
            return
        }

        navigationController?.pushViewController(toVC, animated: true)
    }

    // Shows the VC that handles both Google login & signup.
    private func presentUnifiedGoogleView() {
        guard let toVC = GoogleAuthViewController.instantiate(from: .googleAuth) else {
            DDLogError("Failed to navigate to GoogleAuthViewController from LoginPrologueVC")
            return
        }
        
        navigationController?.pushViewController(toVC, animated: true)
    }

    // Shows the VC that handles only Google signup.
    private func presentGoogleSignupView() {
        guard let toVC = SignupGoogleViewController.instantiate(from: .signup) else {
            DDLogError("Failed to navigate to SignupGoogleViewController from LoginPrologueVC")
            return
        }

        navigationController?.pushViewController(toVC, animated: true)
    }

    private func presentWPLogin() {
        guard let vc = LoginWPComViewController.instantiate(from: .login) else {
            DDLogError("Failed to navigate from LoginPrologueViewController to LoginWPComViewController")
            return
        }
        
        vc.loginFields = self.loginFields
        vc.dismissBlock = dismissBlock
        vc.errorToPresent = errorToPresent
        
        navigationController?.pushViewController(vc, animated: true)
    }
    
    private func presentUnifiedPassword() {
        guard let vc = PasswordViewController.instantiate(from: .password) else {
            DDLogError("Failed to navigate from LoginPrologueViewController to PasswordViewController")
            return
        }
        
        vc.loginFields = loginFields
        navigationController?.pushViewController(vc, animated: true)
    }

}

// MARK: - LoginFacadeDelegate

extension LoginPrologueViewController {

    // Used by SIWA when logging with with a passwordless, 2FA account.
    //
    func needsMultifactorCode(forUserID userID: Int, andNonceInfo nonceInfo: SocialLogin2FANonceInfo) {
        configureViewLoading(false)
        socialNeedsMultifactorCode(forUserID: userID, andNonceInfo: nonceInfo)
    }

}

// MARK: - AppleAuthenticatorDelegate

extension LoginPrologueViewController: AppleAuthenticatorDelegate {

    func showWPComLogin(loginFields: LoginFields) {
        self.loginFields = loginFields

        guard WordPressAuthenticator.shared.configuration.enableUnifiedApple else {
            presentWPLogin()
            return
        }

        presentUnifiedPassword()
    }

    func showApple2FA(loginFields: LoginFields) {
        self.loginFields = loginFields
        signInAppleAccount()
    }
    
    func authFailedWithError(message: String) {
        displayErrorAlert(message, sourceTag: .loginApple)
    }

}

// MARK: - GoogleAuthenticatorLoginDelegate

extension LoginPrologueViewController: GoogleAuthenticatorLoginDelegate {

    func googleFinishedLogin(credentials: AuthenticatorCredentials, loginFields: LoginFields) {
        self.loginFields = loginFields
        syncWPComAndPresentEpilogue(credentials: credentials)
    }

    func googleNeedsMultifactorCode(loginFields: LoginFields) {
        self.loginFields = loginFields

        guard let vc = Login2FAViewController.instantiate(from: .login) else {
            DDLogError("Failed to navigate from LoginViewController to Login2FAViewController")
            return
        }

        vc.loginFields = loginFields
        vc.dismissBlock = dismissBlock
        vc.errorToPresent = errorToPresent

        navigationController?.pushViewController(vc, animated: true)
    }

    func googleExistingUserNeedsConnection(loginFields: LoginFields) {
        self.loginFields = loginFields

        guard let vc = LoginWPComViewController.instantiate(from: .login) else {
            DDLogError("Failed to navigate from Google Login to LoginWPComViewController (password VC)")
            return
        }

        vc.loginFields = loginFields
        vc.dismissBlock = dismissBlock
        vc.errorToPresent = errorToPresent

        navigationController?.pushViewController(vc, animated: true)
    }

    func googleLoginFailed(errorTitle: String, errorDescription: String, loginFields: LoginFields) {
        self.loginFields = loginFields

        let socialErrorVC = LoginSocialErrorViewController(title: errorTitle, description: errorDescription)
        let socialErrorNav = LoginNavigationController(rootViewController: socialErrorVC)
        socialErrorVC.delegate = self
        socialErrorVC.loginFields = loginFields
        socialErrorVC.modalPresentationStyle = .fullScreen
        present(socialErrorNav, animated: true)
    }

}
