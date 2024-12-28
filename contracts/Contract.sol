// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISP } from "@ethsign/sign-protocol-evm/src/interfaces/ISP.sol";
import { Attestation } from "@ethsign/sign-protocol-evm/src/models/Attestation.sol";
import { DataLocation } from "@ethsign/sign-protocol-evm/src/models/DataLocation.sol";

// Enum for the attestation status
enum AttestationStatus { NotInitiated, Pending, Signed, Rejected }

contract Employd {
    // Struct to store Experience details
    struct Experience {
        uint256 id;
        address owner;
        string role;
        string seeker;
        string employerEnsName;
        string startMonth;
        string startYear;
        string endMonth;
        string endYear;
        string employmentType;
        string description; 
        address employerAddress; 
        AttestationStatus attestationStatus;
    }

    // Mappings to store experiences by id and experience ids
    mapping(uint256 => Experience) public experiences;
    uint256[] public experiencesIds;

    // Total number of experiences
    uint256 public totalExperieceCount = 0;

    // Sign Protocol instance
    ISP public spInstance;
    uint64 public schemaId;

    
    // Private function to generate a unique id for experiences
    function generateUniqueId() private view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, address(this))));
    }

    // Function to set the Sign Protocol instance
    function setSPInstance(address instance) public {
        spInstance = ISP(instance);
    }

    function setSchemaID(uint64 schemaId_) public {
        schemaId = schemaId_;
    }

    // Function to add a new experience
    function addExperience(
        string memory _role,
        string memory _seeker,
        string memory _employerEnsName,
        string memory _startMonth,
        string memory _startYear,
        string memory _endMonth,
        string memory _endYear,
        string memory _employmentType,
        string memory _description,
        address _employerAddress
    ) public returns (uint256) {
        uint256 id = generateUniqueId();
    
        // Create and store the experience with added description and skills
        experiences[id] = Experience(
            id,
            msg.sender,
            _role,
            _seeker,
            _employerEnsName,
            _startMonth, 
            _startYear,
            _endMonth,
            _endYear,
            _employmentType,
            _description, 
            _employerAddress,
            AttestationStatus.NotInitiated
        );

        experiencesIds.push(id);
        totalExperieceCount++;

        return id;
    }

    event EmployerChosen(uint256 experienceId, address employerAddress, string employerEns);

     // Function to choose an employerAddress for attestation
    function chooseEmployerForAttestation(uint256 experienceId, address employerAddress) public {
        Experience storage experience = experiences[experienceId];

        // Ensure the caller is the experience owner
        require(msg.sender == experience.owner, "Only the employee can choose the employerAddress");

        // Ensure the status is 'Not Initiated' before proceeding
        require(experience.attestationStatus == AttestationStatus.NotInitiated, "Attestation already initiated");

        experience.employerAddress = employerAddress;

        experience.attestationStatus = AttestationStatus.Pending;

        // Emit event for employerAddress choice
        emit EmployerChosen(experienceId, employerAddress, experience.employerEnsName);
    }


    // Function to sign an attestation for an experience
    function signAttestation(uint256 experienceId) public {
        Experience storage experience = experiences[experienceId];

        // Ensure the attestation is in Pending status, i.e., employerAddress has been chosen
        require(experience.attestationStatus == AttestationStatus.Pending, "Employer must be chosen first");

        // Ensure the sender is the employerAddress that is authorized to sign the attestation
        require(msg.sender == experience.employerAddress, "Only the selected employerAddress can sign the attestation");

        // Create the attestation data
        bytes memory data = abi.encode(
            experience.role,
            experience.employerAddress,
            experience.startMonth,
            experience.startYear,
            experience.endMonth,
            experience.endYear,
            experience.employmentType,
            experience.description
            // experience.skills
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

    // Function to approve an attestation
    function approveAttestation(uint256 experienceId) public {
        Experience storage experience = experiences[experienceId];
        require(experience.attestationStatus == AttestationStatus.Pending, "Attestation not in Pending status");

        // Update the attestation status to Signed
        experience.attestationStatus = AttestationStatus.Signed;

        // Emit event for approval
        emit AttestationApproved(experienceId);
    }

    // Function to reject an attestation
    function rejectAttestation(uint256 experienceId) public {
        Experience storage experience = experiences[experienceId];
        require(experience.attestationStatus == AttestationStatus.Pending, "Attestation not in Pending status");

        // Update the attestation status to Rejected
        experience.attestationStatus = AttestationStatus.Rejected;

        // Emit event for rejection
        emit AttestationRejected(experienceId);
    }

    // Function to get the experience details by experience ID
    function getExperienceById(uint256 experienceId) public view returns (Experience memory) {
        return experiences[experienceId];
    }

    // Events
    event AttestationSigned(uint256 experienceId, address indexed attester, uint64 attestationId);
    event AttestationApproved(uint256 experienceId);
    event AttestationRejected(uint256 experienceId);

    // Function to get all experiences
    function getExperiences() public view returns (Experience[] memory) {
        Experience[] memory allExperiences = new Experience[](totalExperieceCount);

        for (uint i = 0; i < experiencesIds.length; i++) {
            allExperiences[i] = experiences[experiencesIds[i]];
        }

        return allExperiences;
    }

    // Function to get all experiences of a specific user
    function getUserExperience(address _owner) public view returns (Experience[] memory) {
        uint userExperienceCount = 0;
        for (uint i = 0; i < experiencesIds.length; i++) {
            if (experiences[experiencesIds[i]].owner == _owner) {
                userExperienceCount++;
            }
        }

        Experience[] memory userExperiences = new Experience[](userExperienceCount);
        uint index = 0;

        for (uint i = 0; i < experiencesIds.length; i++) {
            if (experiences[experiencesIds[i]].owner == _owner) {
                userExperiences[index] = experiences[experiencesIds[i]];
                index++;
            }
        }

        return userExperiences;
    }

    function getEmployerExperiences(address _employerAddress) public view returns (Experience[] memory) {
        uint employerExperienceCount = 0;
        
        for (uint i = 0; i < experiencesIds.length; i++) {
            if (experiences[experiencesIds[i]].employerAddress == _employerAddress) {
                employerExperienceCount++;
            }
        }

        Experience[] memory employerExperiences = new Experience[](employerExperienceCount);
        uint index = 0;

        for (uint i = 0; i < experiencesIds.length; i++) {
            if (experiences[experiencesIds[i]].employerAddress == _employerAddress) {
                employerExperiences[index] = experiences[experiencesIds[i]];
                index++;
            }
        }

        return employerExperiences;
    }
}