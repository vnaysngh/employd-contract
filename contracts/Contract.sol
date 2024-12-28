// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISP } from "@ethsign/sign-protocol-evm/src/interfaces/ISP.sol";
import { Attestation } from "@ethsign/sign-protocol-evm/src/models/Attestation.sol";
import { DataLocation } from "@ethsign/sign-protocol-evm/src/models/DataLocation.sol";

enum AttestationStatus { NotInitiated, Pending, Signed, Rejected }

contract Employd is Ownable, ReentrancyGuard {
    // Struct to store Experience details
    struct Experience {
        uint256 id;
        address owner;
        string role;
        string seekerName;
        string seekerEnsName;
        string employerName;
        string employerEnsName;
        string startMonth;
        string startYear;
        string endMonth;
        string endYear;
        string employmentType;
        string description;
        address employerAddress;
        address seekerAddress;
        AttestationStatus attestationStatus;
    }

    // Mappings and storage for experiences
    mapping(uint256 => Experience) private experiences;
    mapping(address => uint256[]) private userExperienceIds;
    mapping(address => uint256[]) private employerExperienceIds;
    uint256 private totalExperiences;

    // Sign Protocol instance and schemaId
    ISP private spInstance;
    uint64 private schemaId;

    // Events
    event ExperienceAdded(uint256 experienceId, address indexed owner);
    event EmployerChosen(uint256 experienceId, address indexed employerAddress, string employerEns);
    event AttestationSigned(uint256 experienceId, address indexed employer, uint64 attestationId);
    event AttestationApproved(uint256 experienceId);
    event AttestationRejected(uint256 experienceId);

    // Modifier for valid experience ID
    modifier validExperienceId(uint256 experienceId) {
        require(experiences[experienceId].id != 0, "Experience does not exist");
        _;
    }

    // Private function to generate a unique id for experiences
    function generateUniqueId() private view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, totalExperiences)));
    }

    // Set the Sign Protocol instance
    function setSPInstance(address instance) external onlyOwner {
        spInstance = ISP(instance);
    }

    // Set the schema ID
    function setSchemaID(uint64 schemaId_) external onlyOwner {
        schemaId = schemaId_;
    }

    // Add a new experience
    function addExperience(
        string memory _role,
        string memory _seekerName,
        string memory _seekerEnsName,
        string memory _employerName,
        string memory _employerEnsName,
        string memory _startMonth,
        string memory _startYear,
        string memory _endMonth,
        string memory _endYear,
        string memory _employmentType,
        string memory _description,
        address _employerAddress
    ) external nonReentrant returns (uint256) {
        require(bytes(_role).length > 0, "Role cannot be empty");
        require(bytes(_seekerEnsName).length > 0, "Seeker cannot be empty");
        require(bytes(_employerEnsName).length > 0, "Employer ENS name cannot be empty");
        require(bytes(_startMonth).length > 0 && bytes(_startYear).length > 0, "Start date is required");

        uint256 id = generateUniqueId();
        experiences[id] = Experience({
            id: id,
            owner: msg.sender,
            role: _role,
            seekerName: _seekerName,
            seekerEnsName: _seekerEnsName,
            employerName: _employerName,
            employerEnsName: _employerEnsName,
            startMonth: _startMonth,
            startYear: _startYear,
            endMonth: _endMonth,
            endYear: _endYear,
            employmentType: _employmentType,
            description: _description,
            employerAddress: _employerAddress,
            seekerAddress: msg.sender,
            attestationStatus: AttestationStatus.NotInitiated
        });

        userExperienceIds[msg.sender].push(id);
        totalExperiences++;
        emit ExperienceAdded(id, msg.sender);
        return id;
    }

    // Choose employer for attestation
    function chooseEmployerForAttestation(uint256 experienceId, address employerAddress)
        external
        validExperienceId(experienceId)
        nonReentrant
    {
        Experience storage experience = experiences[experienceId];
        require(msg.sender == experience.owner, "Only the experience owner can assign employer");
        require(employerAddress != address(0), "Invalid employer address");
        require(experience.attestationStatus == AttestationStatus.NotInitiated, "Attestation already initiated");

        experience.employerAddress = employerAddress;
        experience.attestationStatus = AttestationStatus.Pending;
        employerExperienceIds[employerAddress].push(experienceId);

        emit EmployerChosen(experienceId, employerAddress, experience.employerEnsName);
    }

    // Sign attestation
    function signAttestation(uint256 experienceId) external validExperienceId(experienceId) nonReentrant {
        Experience storage experience = experiences[experienceId];
        require(msg.sender == experience.employerAddress, "Only the assigned employer can sign");
        require(experience.attestationStatus == AttestationStatus.Pending, "Attestation is not pending");

        bytes memory data = abi.encode(
            experience.role,
            experience.employerName,
            experience.employerAddress,
            experience.employerEnsName,
            experience.seekerName,
            experience.seekerAddress,
            experience.seekerEnsName,
            experience.startMonth,
            experience.startYear,
            experience.endMonth,
            experience.endYear,
            experience.employmentType
            // experience.description
        );

         // Declare recipients properly as a bytes array
    
        bytes[] memory recipients = new bytes[](1);
        recipients[0] = abi.encode(msg.sender);

        // Create the attestation struct
       Attestation memory a = Attestation({
            schemaId: schemaId,
            linkedAttestationId: 0,
            attestTimestamp: 0,
            revokeTimestamp: 0,
            attester: address(this),
            validUntil: 0,
            dataLocation: DataLocation.ONCHAIN,
            revoked: false,
            recipients: recipients,
            data: data // SignScan assumes this is from `abi.encode(...)`
        });
        // Call the Sign Protocol's attest function
        uint64 attestationId = spInstance.attest(a, "", "", "");
        require(attestationId != 0, "Attestation failed");

        // Update the experience with the attestation details
        experience.attestationStatus = AttestationStatus.Signed;

        // Emit event for attestation
        emit AttestationSigned(experienceId, msg.sender, attestationId);
    }

    // Approve attestation
    function approveAttestation(uint256 experienceId) external validExperienceId(experienceId) {
        Experience storage experience = experiences[experienceId];
        require(experience.attestationStatus == AttestationStatus.Pending, "Attestation is not pending");

        experience.attestationStatus = AttestationStatus.Signed;
        emit AttestationApproved(experienceId);
    }

    // Reject attestation
    function rejectAttestation(uint256 experienceId) external validExperienceId(experienceId) {
        Experience storage experience = experiences[experienceId];
        require(experience.attestationStatus == AttestationStatus.Pending, "Attestation is not pending");

        experience.attestationStatus = AttestationStatus.Rejected;
        emit AttestationRejected(experienceId);
    }

    // Get experience by ID
    function getExperienceById(uint256 experienceId) external view validExperienceId(experienceId) returns (Experience memory) {
        return experiences[experienceId];
    }

    // Get user experiences
    function getUserExperiences(address user) external view returns (Experience[] memory) {
        uint256[] memory ids = userExperienceIds[user];
        Experience[] memory userExperiences = new Experience[](ids.length);

        for (uint256 i = 0; i < ids.length; i++) {
            userExperiences[i] = experiences[ids[i]];
        }

        return userExperiences;
    }

    // Get employer experiences
    function getEmployerExperiences(address employer) external view returns (Experience[] memory) {
        uint256[] memory ids = employerExperienceIds[employer];
        Experience[] memory employerExperiences = new Experience[](ids.length);

        for (uint256 i = 0; i < ids.length; i++) {
            employerExperiences[i] = experiences[ids[i]];
        }

        return employerExperiences;
    }
}