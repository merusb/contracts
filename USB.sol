// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2017, 2018, 2019 dbrock, rain, mrchico

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity >=0.5.12;

// FIXME: This contract was altered compared to the production version.
// It doesn't use LibNote anymore.
// New deployments of this contract will need to include custom events (TO DO).

contract PermitToken {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address guy) external auth { wards[guy] = 1; }
    function deny(address guy) external auth { wards[guy] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "not-authorized");
        _;
    }

    // --- ERC20 Data ---
    string  public constant version  = "1";
    //string  public constant name     = "USB Stablecoin";
    //string  public constant symbol   = "USB";
    //uint8   public constant decimals = 18;
    string  public name;
    string  public symbol;
    uint8   public decimals;
    uint256 public totalSupply;

    mapping (address => uint)                       public balanceOf;
    mapping (address => mapping (address => uint))  public allowance;
    mapping (address => uint)                       public nonces;

    event Approval(address indexed src, address indexed guy, uint wad);
    event Transfer(address indexed src, address indexed dst, uint wad);

    // --- Math ---
    function _add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }
    function _sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }

    // --- EIP712 niceties ---
    bytes32 public DOMAIN_SEPARATOR;
    // bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address holder,address spender,uint256 nonce,uint256 expiry,bool allowed)");
    //bytes32 public constant PERMIT_TYPEHASH = 0xea2aa0a1be11a07ed86d755c93467f4f82362b452371d1ba94d1715123511acb;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) public {
        __PermitToken_init(name_, symbol_, decimals_);
    }
	
	function __PermitToken_init(string memory name_, string memory symbol_, uint8 decimals_) public {
		require(bytes32(0) == DOMAIN_SEPARATOR);
        wards[msg.sender] = 1;
		name = name_;
		symbol = symbol_;
		decimals = decimals_;
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(name_)),
            keccak256(bytes(version)),
            _chainId(),
            address(this)
        ));
	}

    function _chainId() internal pure returns (uint id) {
        assembly { id := chainid() }
    }
    
    // --- Token ---
    function transfer(address dst, uint wad) external returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }
    function transferFrom(address src, address dst, uint wad)
        public returns (bool)
    {
        require(balanceOf[src] >= wad, "insufficient-balance");
        if (src != msg.sender && allowance[src][msg.sender] != uint(-1)) {
            require(allowance[src][msg.sender] >= wad, "insufficient-allowance");
            allowance[src][msg.sender] = _sub(allowance[src][msg.sender], wad);
        }
        balanceOf[src] = _sub(balanceOf[src], wad);
        balanceOf[dst] = _add(balanceOf[dst], wad);
        emit Transfer(src, dst, wad);
        return true;
    }
    function mint(address usr, uint wad) public auth {
        balanceOf[usr] = _add(balanceOf[usr], wad);
        totalSupply    = _add(totalSupply, wad);
        emit Transfer(address(0), usr, wad);
    }
    function burn(address usr, uint wad) external {
        require(balanceOf[usr] >= wad, "insufficient-balance");
        if (usr != msg.sender && allowance[usr][msg.sender] != uint(-1)) {
            require(allowance[usr][msg.sender] >= wad, "insufficient-allowance");
            allowance[usr][msg.sender] = _sub(allowance[usr][msg.sender], wad);
        }
        balanceOf[usr] = _sub(balanceOf[usr], wad);
        totalSupply    = _sub(totalSupply, wad);
        emit Transfer(usr, address(0), wad);
    }
    function approve(address usr, uint wad) external returns (bool) {
        allowance[msg.sender][usr] = wad;
        emit Approval(msg.sender, usr, wad);
        return true;
    }

    // --- Alias ---
    function push(address usr, uint wad) external {
        transferFrom(msg.sender, usr, wad);
    }
    function pull(address usr, uint wad) external {
        transferFrom(usr, msg.sender, wad);
    }
    function move(address src, address dst, uint wad) external {
        transferFrom(src, dst, wad);
    }

    // --- Approve by signature ---
    //function permit(address holder, address spender, uint256 nonce, uint256 expiry,
    //                bool allowed, uint8 v, bytes32 r, bytes32 s) external
    //{
    //    bytes32 digest =
    //        keccak256(abi.encodePacked(
    //            "\x19\x01",
    //            DOMAIN_SEPARATOR,
    //            keccak256(abi.encode(PERMIT_TYPEHASH,
    //                                 holder,
    //                                 spender,
    //                                 nonce,
    //                                 expiry,
    //                                 allowed))
    //    ));
    //
    //    require(holder != address(0), "invalid-address-0");
    //    require(holder == ecrecover(digest, v, r, s), "invalid-permit");
    //    require(expiry == 0 || now <= expiry, "permit-expired");
    //    require(nonce == nonces[holder]++, "invalid-nonce");
    //    uint wad = allowed ? uint(-1) : 0;
    //    allowance[holder][spender] = wad;
    //    emit Approval(holder, spender, wad);
    //}
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, 'permit EXPIRED');
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'permit INVALID_SIGNATURE');
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }
}


contract USB is PermitToken {
    constructor() public PermitToken("USB Stablecoin kurtosis.finance", "USB", 18) {
    }
	
	function __USB_init() external {
        __PermitToken_init("USB Stablecoin kurtosis.finance", "USB", 18);
    }
}

contract KIS is PermitToken {
    constructor() public PermitToken("KurtosIS.finance", "KIS", 18) {
        mint(msg.sender, 1_000_000_000e18);
    }
	
	function __KIS_init() external {
        __PermitToken_init("KurtosIS.finance", "KIS", 18);
        mint(msg.sender, 1_000_000_000e18);
    }
}

