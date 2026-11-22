// OpenZiti Setup Logs Console Logic
document.addEventListener('DOMContentLoaded', () => {
    const POLL_INTERVAL_MS = 1500;
    let pollInterval = null;

    // Status tracking state
    let isZitiSetupLogFinished = false;
    let isZtAppRunning = false;
    let isControllerRunning = false;
    let hasSetupFailed = false;

    // Helper to update node status border and light in the topology diagram
    function updateTopologyNodeStatus(nodeId, dotId, status) {
        const nodeEl = document.getElementById(nodeId);
        const dotEl = document.getElementById(dotId);
        if (!nodeEl || !dotEl) return;
        
        nodeEl.classList.remove('status-online', 'status-offline', 'status-provisioning', 'status-completed');
        dotEl.className = 'topo-status-dot';
        
        // Dynamic status text update for the setup node
        if (nodeId === 'node-ziti-setup') {
            const setupValEl = document.getElementById('setup-topo-status-val');
            if (setupValEl) {
                if (status === 'completed') {
                    setupValEl.textContent = 'COMPLETED (EXITED)';
                    setupValEl.className = 'val text-success';
                } else if (status === 'provisioning') {
                    setupValEl.textContent = 'PROVISIONING';
                    setupValEl.className = 'val text-highlight';
                } else if (status === 'offline') {
                    setupValEl.textContent = 'FAILED';
                    setupValEl.className = 'val text-warning';
                } else {
                    setupValEl.textContent = 'WAITING';
                    setupValEl.className = 'val';
                }
            }
        }
        
        if (status === 'online') {
            nodeEl.classList.add('status-online');
            dotEl.classList.add('online');
        } else if (status === 'completed') {
            nodeEl.classList.add('status-completed');
            dotEl.classList.add('completed');
        } else if (status === 'provisioning') {
            nodeEl.classList.add('status-provisioning');
            dotEl.classList.add('provisioning');
        } else {
            nodeEl.classList.add('status-offline');
            dotEl.classList.add('offline');
        }
    }

    // DOM Elements
    const terminalOutput = document.getElementById('terminal-log');
    const copyButton = document.getElementById('btn-copy-logs');
    const statusBadge = document.getElementById('setup-status-badge');
    const statusText = statusBadge.querySelector('.status-text');
    const statusDot = statusBadge.querySelector('.status-dot');
    const milestonesContainer = document.getElementById('milestones');

    // Milestones Configuration
    const milestones = [
        {
            id: 'hostname-resolution',
            label: 'Hostname Resolution',
            desc: 'Checking /etc/hosts entries for required hostnames',
            activeTrigger: null,
            successTrigger: null
        },
        {
            id: 'controller-check',
            label: 'Controller Availability',
            desc: 'Waiting for Edge API listener',
            activeTrigger: 'Waiting for OpenZiti controller to start...',
            successTrigger: 'Controller is up! Logging in...'
        },
        {
            id: 'controller-auth',
            label: 'Edge Controller Login',
            desc: 'Authenticating administrator session',
            activeTrigger: 'Controller is up! Logging in...',
            successTrigger: 'Checking intercept config...'
        },
        {
            id: 'intercept-config',
            label: 'Intercept Configuration',
            desc: 'Creating zt-app-intercept rules',
            activeTrigger: 'Checking intercept config...',
            successTrigger: 'Checking zt-app service...'
        },
        {
            id: 'secure-service',
            label: 'Secure Service Bind',
            desc: 'Creating zt-app-secure-ui edge service',
            activeTrigger: 'Checking zt-app service...',
            successTrigger: 'Checking zt-app identity...'
        },
        {
            id: 'identities-ca',
            label: 'Identity Provisioning',
            desc: 'Enrolling client/app identities & CA',
            activeTrigger: 'Checking zt-app identity...',
            successTrigger: 'Extracting CA certificate...'
        },
        {
            id: 'policies-config',
            label: 'Access Policies',
            desc: 'Applying bind, dial, and router policies',
            activeTrigger: 'Checking service policy',
            successTrigger: 'Ziti network setup complete!'
        }
    ];

    // Initial render of milestone cards
    function renderMilestones() {
        milestonesContainer.innerHTML = '';
        milestones.forEach((m) => {
            const card = document.createElement('div');
            card.className = 'milestone-item pending';
            card.id = `milestone-${m.id}`;
            
            card.innerHTML = `
                <div class="milestone-status-icon">
                    <svg class="icon-pending" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3">
                        <circle cx="12" cy="12" r="10"></circle>
                    </svg>
                    <svg class="icon-active" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3">
                        <circle cx="12" cy="12" r="10"></circle>
                        <path d="M12 6v6l4 2"></path>
                    </svg>
                    <svg class="icon-success" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3">
                        <polyline points="20 6 9 17 4 12"></polyline>
                    </svg>
                    <svg class="icon-error" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3">
                        <circle cx="12" cy="12" r="10"></circle>
                        <line x1="15" y1="9" x2="9" y2="15"></line>
                        <line x1="9" y1="9" x2="15" y2="15"></line>
                    </svg>
                </div>
                <div class="milestone-details">
                    <h3>${m.label}</h3>
                    <p>${m.desc}</p>
                </div>
            `;
            milestonesContainer.appendChild(card);
        });
    }

    // Update individual milestone visual state
    function setMilestoneState(id, state) {
        const el = document.getElementById(`milestone-${id}`);
        if (!el) return;
        el.className = `milestone-item ${state}`;
    }

    // Update global status badge
    function updateGlobalStatus(status, text) {
        statusBadge.className = `console-status-badge status-${status}`;
        statusText.textContent = text;
    }

    function updateMilestoneDescription(id, text) {
        const el = document.getElementById(`milestone-${id}`);
        if (!el) return;
        const descriptionEl = el.querySelector('.milestone-details p');
        if (descriptionEl) {
            descriptionEl.textContent = text;
        }
    }

    /**
     * DNS resolution check. Probes each required hostname on port 8080 where
     * the menu nginx container is guaranteed to be listening (it serves this
     * page). If a hostname resolves to 127.0.0.1 via /etc/hosts, nginx will
     * respond. A TypeError means the hostname cannot be resolved at all.
     */
    async function checkHostnameResolution() {
        const milestoneId = 'hostname-resolution';
        setMilestoneState(milestoneId, 'active');
        updateMilestoneDescription(milestoneId, 'Resolving local hostnames...');

        const requiredHosts = [
            'app.local',
            'menu.local',
            'ziti-controller.local',
            'zt.local'
        ];

        const results = await Promise.all(requiredHosts.map(async (host) => {
            try {
                const controller = new AbortController();
                const timeoutId = window.setTimeout(() => controller.abort(), 3000);
                // Probe port 8080 — the menu nginx container listens here and
                // will respond for ANY hostname that resolves to 127.0.0.1.
                // mode: 'no-cors' avoids CORS preflight issues.
                await fetch(`http://${host}:8080/`, {
                    method: 'HEAD',
                    mode: 'no-cors',
                    cache: 'no-store',
                    signal: controller.signal
                });
                window.clearTimeout(timeoutId);
                return { host, resolved: true };
            } catch (error) {
                if (error.name === 'AbortError') {
                    // Timeout — connection hung, but DNS must have resolved
                    return { host, resolved: true };
                }
                // TypeError — hostname could not be resolved (ERR_NAME_NOT_RESOLVED)
                return { host, resolved: false };
            }
        }));

        const missing = results.filter(r => !r.resolved).map(r => r.host);
        const allResolved = missing.length === 0;
        setMilestoneState(milestoneId, allResolved ? 'success' : 'error');
        updateMilestoneDescription(
            milestoneId,
            allResolved
                ? 'All hostnames resolve — /etc/hosts is configured correctly.'
                : `Cannot resolve: ${missing.join(', ')}. Check your /etc/hosts file.`
        );
        updateTopologyNodeStatus('node-dns-server', 'dns-status-dot', allResolved ? 'online' : 'offline');
        return allResolved;
    }

    // Update overall dashboard status dynamically
    function updateOverallStatus() {
        if (hasSetupFailed) {
            updateGlobalStatus('error', 'Failed');
            return;
        }

        if (!isZitiSetupLogFinished) {
            // Logs are still active or waiting
            return; // let fetchLogs handle status updating during provisioning
        }

        // Setup log is finished! Check if controller API and ZT App are running
        if (!isZtAppRunning || !isControllerRunning) {
            updateGlobalStatus('waiting', 'Starting Services');
        } else {
            updateGlobalStatus('success', 'Complete');
        }
    }

    // Fetch and parse setup log
    async function fetchLogs() {
        try {
            const response = await fetch('/ziti-setup.log');
            if (response.status === 404) {
                // Log file doesn't exist yet, provisioning is starting
                terminalOutput.textContent = 'Waiting for provisioning container to initialize and write logs...';
                updateGlobalStatus('waiting', 'Starting Up');
                return;
            }

            if (!response.ok) {
                throw new Error(`Failed to fetch logs: ${response.status} ${response.statusText}`);
            }

            const logText = await response.text();
            
            // Check if log changed or is empty
            if (!logText.trim()) {
                terminalOutput.textContent = 'Initializing OpenZiti container...';
                updateGlobalStatus('waiting', 'Initializing');
                return;
            }

            // Update terminal text
            const shouldScroll = (terminalOutput.scrollHeight - terminalOutput.clientHeight - terminalOutput.scrollTop) < 50;
            terminalOutput.textContent = logText;
            if (shouldScroll) {
                terminalOutput.scrollTop = terminalOutput.scrollHeight;
            }

            // Process milestones
            let currentActiveIndex = -1;
            let setupFailed = logText.toLowerCase().includes('error:') || logText.toLowerCase().includes('fatal');
            let setupFinished = logText.includes('Ziti network setup complete!');

            milestones.forEach((m, idx) => {
                const hasSuccess = logText.includes(m.successTrigger) || (setupFinished && idx < milestones.length);
                const hasActive = logText.includes(m.activeTrigger);

                if (hasSuccess) {
                    setMilestoneState(m.id, 'success');
                } else if (hasActive && !setupFailed) {
                    setMilestoneState(m.id, 'active');
                    currentActiveIndex = idx;
                } else if (setupFailed && currentActiveIndex === idx - 1) {
                    setMilestoneState(m.id, 'error');
                } else {
                    setMilestoneState(m.id, 'pending');
                }
            });

            // Update global dashboard status
            if (setupFinished) {
                isZitiSetupLogFinished = true;
                setMilestoneState(milestones[milestones.length - 1].id, 'success');
                updateOverallStatus();
            } else if (setupFailed) {
                hasSetupFailed = true;
                updateOverallStatus();
                // Set the current pending or active milestone to error
                const activeOrPending = milestones.find((m, idx) => {
                    const el = document.getElementById(`milestone-${m.id}`);
                    return el && (el.classList.contains('active') || el.classList.contains('pending'));
                });
                if (activeOrPending) {
                    setMilestoneState(activeOrPending.id, 'error');
                }
            } else {
                isZitiSetupLogFinished = false;
                hasSetupFailed = false;
                updateGlobalStatus('active', 'Provisioning');
            }

        } catch (error) {
            console.error('Error polling setup logs:', error);
            terminalOutput.textContent = `Error loading setup logs: ${error.message}`;
            updateGlobalStatus('error', 'Fetch Error');
        }
    }

    // Copy to clipboard
    copyButton.addEventListener('click', () => {
        const text = terminalOutput.textContent;
        navigator.clipboard.writeText(text).then(() => {
            const originalText = copyButton.textContent;
            copyButton.textContent = 'Copied!';
            copyButton.classList.add('copied');
            setTimeout(() => {
                copyButton.textContent = originalText;
                copyButton.classList.remove('copied');
            }, 2000);
        }).catch((err) => {
            console.error('Clipboard copy failed: ', err);
        });
    });

    // Service status poller.
    // Uses unprivileged HTTP health probes proxied by the menu nginx container
    // (no Docker socket access — exposing the Docker API to a browser is root on the host).
    const ztContainerStatusText = document.getElementById('zt-container-status-text');
    const standardContainerStatusText = document.getElementById('standard-container-status-text');

    const STATUS_PROBE_TIMEOUT_MS = 2500;
    const HEARTBEAT_MAX_AGE_SECONDS = 15;

    async function probe(url) {
        const controller = new AbortController();
        const timeoutId = window.setTimeout(() => controller.abort(), STATUS_PROBE_TIMEOUT_MS);
        try {
            const response = await fetch(url, { cache: 'no-store', signal: controller.signal });
            return response;
        } catch (error) {
            return null;
        } finally {
            window.clearTimeout(timeoutId);
        }
    }

    async function isHttpHealthy(url) {
        const response = await probe(url);
        return Boolean(response && response.ok);
    }

    async function isZtAppHeartbeatFresh() {
        const response = await probe('/status/zt-app-heartbeat.txt');
        if (!response || !response.ok) return false;
        const epochSeconds = parseInt((await response.text()).trim(), 10);
        if (Number.isNaN(epochSeconds)) return false;
        return (Date.now() / 1000) - epochSeconds <= HEARTBEAT_MAX_AGE_SECONDS;
    }

    function renderContainerStatus(element, isRunning) {
        if (!element) return;
        element.innerHTML = isRunning
            ? '<span class="status-indicator indicator-running"></span>RUNNING'
            : '<span class="status-indicator indicator-offline"></span>OFFLINE';
        element.className = `stat-val font-mono ${isRunning ? 'text-running' : 'text-offline'}`;
    }

    function renderSetupStatus() {
        const setupNodeStatusVal = document.getElementById('setup-node-status-val');
        let dotState = 'provisioning';
        let label = 'PROVISIONING';
        let cssClass = 'val text-warning';
        if (hasSetupFailed) {
            dotState = 'offline';
            label = 'FAILED';
            cssClass = 'val text-danger';
        } else if (isZitiSetupLogFinished) {
            dotState = 'completed';
            label = 'COMPLETED';
            cssClass = 'val text-success';
        }
        updateTopologyNodeStatus('node-ziti-setup', 'setup-status-dot', dotState);
        if (setupNodeStatusVal) {
            setupNodeStatusVal.textContent = label;
            setupNodeStatusVal.className = cssClass;
        }
    }

    async function pollServiceStatus() {
        const [dnsRunning, ctrlRunning, appRunning, ztRunning] = await Promise.all([
            isHttpHealthy('/api/dns-status'),
            isHttpHealthy('/edge/client/v1/version'),
            isHttpHealthy('/api/app-status'),
            isZtAppHeartbeatFresh()
        ]);

        updateTopologyNodeStatus('node-dns-server', 'dns-status-dot', dnsRunning ? 'online' : 'offline');
        // This page is served by the menu container, so it is online by definition.
        updateTopologyNodeStatus('node-menu-nginx', 'menu-status-dot', 'online');

        isControllerRunning = ctrlRunning;
        updateTopologyNodeStatus('node-ziti-controller', 'controller-status-dot', ctrlRunning ? 'online' : 'offline');

        updateTopologyNodeStatus('node-app-local', 'app-status-dot', appRunning ? 'online' : 'offline');
        renderContainerStatus(standardContainerStatusText, appRunning);

        isZtAppRunning = ztRunning;
        updateTopologyNodeStatus('node-zt-app-local', 'ztapp-status-dot', ztRunning ? 'online' : 'offline');
        renderContainerStatus(ztContainerStatusText, ztRunning);

        renderSetupStatus();
        updateOverallStatus();
    }

    // Zero-Trust client access check via browser fetch to intercept hostname
    const ztClientStatusText = document.getElementById('zt-client-status-text');
    const ztClientTopoStatusDot = document.getElementById('zt-client-topo-status-dot');
    const ztClientTopoStatusVal = document.getElementById('zt-client-topo-status-val');
    const subnodeZitiClient = document.getElementById('subnode-ziti-client');

    async function checkZtClientAccess() {
        let timeoutId;
        try {
            const controller = new AbortController();
            timeoutId = window.setTimeout(() => controller.abort(), 2000);
            
            // Try fetching the ZT app hello endpoint over the overlay network
            // mode: 'no-cors' sends the request without triggering CORS preflight errors
            await fetch('http://zt-app-local:8080/hello', {
                method: 'HEAD',
                mode: 'no-cors',
                cache: 'no-store',
                signal: controller.signal
            });
            window.clearTimeout(timeoutId);
            updateZtClientStatus(true);
        } catch (error) {
            window.clearTimeout(timeoutId);
            updateZtClientStatus(false);
        }
    }

    function updateZtClientStatus(isEnrolled) {
        if (isEnrolled) {
            if (ztClientStatusText) {
                ztClientStatusText.innerHTML = '<span class="status-indicator indicator-running"></span>ENROLLED &amp; SECURED';
                ztClientStatusText.className = 'stat-val font-mono text-running';
            }
            if (ztClientTopoStatusDot) {
                ztClientTopoStatusDot.className = 'topo-sub-status-dot online';
            }
            if (ztClientTopoStatusVal) {
                ztClientTopoStatusVal.textContent = 'SECURED';
                ztClientTopoStatusVal.className = 'val text-success';
            }
            if (subnodeZitiClient) {
                subnodeZitiClient.style.borderColor = 'rgba(16, 185, 129, 0.4)';
                subnodeZitiClient.style.background = 'rgba(16, 185, 129, 0.05)';
            }
        } else {
            if (ztClientStatusText) {
                ztClientStatusText.innerHTML = '<span class="status-indicator indicator-offline"></span>NOT ENROLLED';
                ztClientStatusText.className = 'stat-val font-mono text-offline';
            }
            if (ztClientTopoStatusDot) {
                ztClientTopoStatusDot.className = 'topo-sub-status-dot offline';
            }
            if (ztClientTopoStatusVal) {
                ztClientTopoStatusVal.textContent = 'UNENROLLED';
                ztClientTopoStatusVal.className = 'val text-warning';
            }
            if (subnodeZitiClient) {
                subnodeZitiClient.style.borderColor = 'rgba(192, 132, 252, 0.2)';
                subnodeZitiClient.style.background = 'rgba(192, 132, 252, 0.03)';
            }
        }
    }

    // Run — hostname resolution is checked first as a prerequisite
    renderMilestones();
    checkHostnameResolution().then(() => {
        fetchLogs(); // Run once immediately
        pollInterval = setInterval(fetchLogs, POLL_INTERVAL_MS);
    });

    pollServiceStatus(); // Run once immediately
    setInterval(pollServiceStatus, 3000);

    checkZtClientAccess(); // Run once immediately
    setInterval(checkZtClientAccess, 3000);

    // Instructions Modal toggle
    const instructionsModal = document.getElementById('instructions-modal');
    const showInstructionsBtn = document.getElementById('btn-show-instructions');
    const closeInstructionsBtn = document.getElementById('btn-close-modal');

    if (showInstructionsBtn && instructionsModal && closeInstructionsBtn) {
        showInstructionsBtn.addEventListener('click', () => {
            instructionsModal.classList.add('active');
        });

        closeInstructionsBtn.addEventListener('click', () => {
            instructionsModal.classList.remove('active');
        });

        // Close when clicking outside content area
        instructionsModal.addEventListener('click', (e) => {
            if (e.target === instructionsModal) {
                instructionsModal.classList.remove('active');
            }
        });
    }
    // Console Collapse toggle
    const consoleCard = document.getElementById('console-card');
    const consoleToggle = document.getElementById('console-header-toggle');

    if (consoleToggle && consoleCard) {
        consoleToggle.addEventListener('click', (e) => {
            const clickedBtn = e.target.closest('button');
            if (e.target.closest('a') || (clickedBtn && clickedBtn.id !== 'btn-collapse-console')) {
                return;
            }
            consoleCard.classList.toggle('collapsed');
        });
    }

    // --- Topology Map Logic ---
    const topologyCard = document.getElementById('topology-card');
    const topologyToggle = document.getElementById('topology-header-toggle');
    const flowSelector = document.getElementById('flow-selector');
    const topologyContainer = document.getElementById('topology-svg-container');

    function getPortCoordinates(portId) {
        const port = document.getElementById(portId);
        const container = document.getElementById('topology-svg-container');
        if (!port || !container) return { x: 0, y: 0 };
        const portRect = port.getBoundingClientRect();
        const containerRect = container.getBoundingClientRect();
        return {
            x: portRect.left - containerRect.left + portRect.width / 2,
            y: portRect.top - containerRect.top + portRect.height / 2
        };
    }

    function updateConnections() {
        if (!topologyCard || topologyCard.classList.contains('collapsed')) return;
        
        const paths = [
            { id: 'path-dns', start: 'port-browser-out', end: 'port-dns-in', type: 'bezier-h' },
            { id: 'path-std-1', start: 'port-browser-out', end: 'port-nginx-in', type: 'bezier-h' },
            { id: 'path-std-2', start: 'port-nginx-out-std', end: 'port-app-in', type: 'bezier-h' },
            { id: 'path-zt-1', start: 'port-client-out', end: 'port-overlay-in', type: 'bezier-h' },
            { id: 'path-zt-2', start: 'port-overlay-out', end: 'port-ztapp-in', type: 'bezier-h' },
            { id: 'path-setup', start: 'port-setup-out', end: 'port-ctrl-setup-in', type: 'bezier-v' }
        ];

        paths.forEach(p => {
            const pathEl = document.getElementById(p.id);
            if (!pathEl) return;

            const startPt = getPortCoordinates(p.start);
            const endPt = getPortCoordinates(p.end);
            
            if (startPt.x === 0 && startPt.y === 0) {
                pathEl.setAttribute('d', '');
                return;
            }

            let d = '';
            if (p.type === 'bezier-h') {
                const controlOffset = Math.abs(endPt.x - startPt.x) * 0.4;
                d = `M ${startPt.x} ${startPt.y} C ${startPt.x + controlOffset} ${startPt.y}, ${endPt.x - controlOffset} ${endPt.y}, ${endPt.x} ${endPt.y}`;
            } else if (p.type === 'bezier-v') {
                const controlOffset = Math.abs(endPt.y - startPt.y) * 0.5;
                d = `M ${startPt.x} ${startPt.y} C ${startPt.x} ${startPt.y + controlOffset}, ${endPt.x} ${endPt.y - controlOffset}, ${endPt.x} ${endPt.y}`;
            } else {
                d = `M ${startPt.x} ${startPt.y} L ${endPt.x} ${endPt.y}`;
            }

            pathEl.setAttribute('d', d);
        });
    }

    // Bind collapse toggler
    if (topologyToggle && topologyCard) {
        topologyToggle.addEventListener('click', (e) => {
            // Avoid toggling if flow selector or collapse chevron button was clicked directly
            const clickedBtn = e.target.closest('button');
            const clickedFlow = e.target.closest('#flow-selector');
            if (clickedFlow || (clickedBtn && clickedBtn.id !== 'btn-collapse-topology')) {
                return;
            }
            topologyCard.classList.toggle('collapsed');
            if (!topologyCard.classList.contains('collapsed')) {
                // Wait for the collapse animation to play out, updating coordinates dynamically
                let count = 0;
                const animInterval = setInterval(() => {
                    updateConnections();
                    if (++count > 25) clearInterval(animInterval);
                }, 16);
            }
        });
    }

    // Bind flow buttons
    if (flowSelector && topologyContainer) {
        const flowButtons = flowSelector.querySelectorAll('.flow-btn');
        flowButtons.forEach(btn => {
            btn.addEventListener('click', (e) => {
                e.stopPropagation(); // Avoid triggering header collapse toggle
                const flow = btn.getAttribute('data-flow');
                flowSelector.setAttribute('data-active-flow', flow);
                topologyContainer.setAttribute('data-flow', flow);
                
                // Update active class on buttons
                flowButtons.forEach(b => b.classList.toggle('active', b === btn));
                updateConnections();
            });
        });
        
        // Initialize attributes
        flowSelector.setAttribute('data-active-flow', 'all');
        topologyContainer.setAttribute('data-flow', 'all');
    }

    // Update connections on window resize
    window.addEventListener('resize', updateConnections);
    
    // Initial draw and helper interval to make sure connections align with any rendering delays
    setTimeout(updateConnections, 50);
    setTimeout(updateConnections, 500);
    setTimeout(updateConnections, 1000);
    
    // Periodically redraw connections in case of other dynamic page size changes
    setInterval(updateConnections, 2000);
});
