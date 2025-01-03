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
    // Struct using uint32 for ID
    struct Experience {
        uint32 id;
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

    // Storage using uint32
    mapping(uint32 => Experience) private experiences;
    mapping(address => uint32[]) private userExperienceIds;
    mapping(address => uint32[]) private employerExperienceIds;
    uint32 private nextId = 1;

    // Sign Protocol instance and schemaId
    ISP private spInstance;
    uint64 private schemaId;

    // Events using uint32 and indexed parameters
    event ExperienceAdded(uint32 indexed experienceId, address indexed owner);
    event EmployerChosen(uint32 indexed experienceId, address indexed employerAddress, string employerEns);
    event AttestationSigned(uint32 indexed experienceId, address indexed seeker, address indexed employer, uint64 attestationId);
    event AttestationRejected(uint32 indexed experienceId);

    modifier validExperienceId(uint32 experienceId) {
        require(experiences[experienceId].id != 0, "Experience does not exist");
        _;
    }

    // Admin functions
    function setSPInstance(address instance) external onlyOwner {
        spInstance = ISP(instance);
    }

    function setSchemaID(uint64 schemaId_) external onlyOwner {
        schemaId = schemaId_;
    }

    // Main functions
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
    ) external nonReentrant returns (uint32) {
        require(bytes(_role).length > 0, "Role cannot be empty");
        require(bytes(_seekerEnsName).length > 0, "Seeker cannot be empty");
        require(bytes(_employerEnsName).length > 0, "Employer ENS name cannot be empty");
        require(bytes(_startMonth).length > 0 && bytes(_startYear).length > 0, "Start date is required");

        uint32 id = nextId++;
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
        emit ExperienceAdded(id, msg.sender);
        return id;
    }

    function chooseEmployerForAttestation(uint32 experienceId, address employerAddress)
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

    function signAttestation(uint32 experienceId, address seeker) 
        external 
        validExperienceId(experienceId) 
        nonReentrant 
    {
        Experience storage experience = experiences[experienceId];
        require(experience.seekerAddress == seeker, "Provided seeker does not match the experience seeker");
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
        );

        bytes[] memory recipients = new bytes[](2);
        recipients[0] = abi.encode(seeker);
        recipients[1] = abi.encode(msg.sender);

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
            data: data
        });

        uint64 attestationId = spInstance.attest(a, "", "", "");
        require(attestationId != 0, "Attestation failed");

        experience.attestationStatus = AttestationStatus.Signed;
        emit AttestationSigned(experienceId, seeker, msg.sender, attestationId);
    }

    function rejectAttestation(uint32 experienceId) external validExperienceId(experienceId) {
        Experience storage experience = experiences[experienceId];
        require(experience.attestationStatus == AttestationStatus.Pending, "Attestation is not pending");

        experience.attestationStatus = AttestationStatus.Rejected;
        emit AttestationRejected(experienceId);
    }

    // View functions
    function getExperienceById(uint32 experienceId) 
        external 
        view 
        validExperienceId(experienceId) 
        returns (Experience memory) 
    {
        return experiences[experienceId];
    }

    function getUserExperiences(address user) external view returns (Experience[] memory) {
        uint32[] memory ids = userExperienceIds[user];
        Experience[] memory userExperiences = new Experience[](ids.length);

        for (uint256 i = 0; i < ids.length; i++) {
            userExperiences[i] = experiences[ids[i]];
        }

        return userExperiences;
    }

    function getEmployerExperiences(address employer) external view returns (Experience[] memory) {
        uint32[] memory ids = employerExperienceIds[employer];
        Experience[] memory employerExperiences = new Experience[](ids.length);

        for (uint256 i = 0; i < ids.length; i++) {
            employerExperiences[i] = experiences[ids[i]];
        }

        return employerExperiences;
    }

    // Fetch array of experience IDs for a user
    function getUserExperienceIds(address user) 
        external 
        view 
        returns (uint32[] memory) 
    {
        return userExperienceIds[user];
    }

    // Fetch array of experience IDs for an employer
    function getEmployerExperienceIds(address employer) 
        external 
        view 
        returns (uint32[] memory) 
    {
        return employerExperienceIds[employer];
    }
}